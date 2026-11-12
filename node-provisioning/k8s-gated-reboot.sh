#!/bin/bash
# Host-local, NOT GitOps-managed: deployed by hand to /usr/local/sbin/ on every
# node, run by k8s-gated-reboot.timer at the node's staggered reboot slot. See
# RUNBOOK.md "0f. Automatic reboot for security updates".
#
# Replaces unattended-upgrades' own Automatic-Reboot, which is a blind per-node
# timer. On 2026-11-12 that rebooted all four nodes, 15 minutes apart, onto
# kernel 7.0.0-1023-raspi, which broke container AppArmor: k8s-1 broke its DBs
# at 04:32 and k8s-2/k8s-3 followed anyway (tm 17f100eb).
#
# Reboots only if a reboot is pending AND the cluster looks healthy in
# Prometheus. Otherwise it holds and posts a NodeRebootHeld alert to
# Alertmanager, which health-monitor bridges into a tm task. A held reboot is
# retried at the same slot the next day.
#
# Usage: k8s-gated-reboot [--dry-run]   (--dry-run: decide and print, no alert, no reboot)
set -uo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

NODE=$(hostname)
COREDNS=10.43.0.10
log() { echo "$*"; logger -t k8s-gated-reboot "$*"; }

if [ ! -f /run/reboot-required ] && [ "$DRY_RUN" = 0 ]; then
  exit 0
fi

resolve() { dig +short +time=3 +tries=2 @"$COREDNS" "$1" | head -1; }
PROM=$(resolve kube-prometheus-stack-prometheus.monitoring.svc.cluster.local)
AM=$(resolve kube-prometheus-stack-alertmanager.monitoring.svc.cluster.local)

# Prints the number of series matching a PromQL query, or "ERR".
count_series() {
  local out
  out=$(curl -sf -m 10 --get "http://$PROM:9090/api/v1/query" --data-urlencode "query=$1") || { echo ERR; return; }
  jq -r 'if .status == "success" then (.data.result | length) else "ERR" end' <<<"$out" 2>/dev/null || echo ERR
}

post_alert() {  # $1 = endsAt (RFC3339), $2 = summary
  [ -n "$AM" ] || return 1
  jq -n --arg node "$NODE" --arg ends "$1" --arg summary "$2" '[{
    labels: {alertname: "NodeRebootHeld", node: $node, severity: "warning"},
    annotations: {summary: $summary},
    endsAt: $ends
  }]' | curl -sf -m 10 -o /dev/null -H 'Content-Type: application/json' \
      --data-binary @- "http://$AM:9093/api/v2/alerts"
}

reasons=()
if [ -z "$PROM" ]; then
  reasons+=("cannot resolve Prometheus via CoreDNS ($COREDNS)")
else
  # Silence must never read as healthy: no kube-state-metrics data means the
  # checks below would all come back empty.
  ksm=$(count_series 'up{job="kube-state-metrics"} == 1')
  if [ "$ksm" = ERR ] || [ "$ksm" -lt 1 ]; then
    reasons+=("kube-state-metrics not up in Prometheus (got: $ksm)")
  else
    check() {  # $1 = description, $2 = query that must return no series
      local n; n=$(count_series "$2")
      if [ "$n" = ERR ]; then reasons+=("query failed: $1")
      elif [ "$n" -gt 0 ]; then reasons+=("$n $1"); fi
    }
    check "node(s) not Ready" \
      'kube_node_status_condition{condition="Ready",status="true"} == 0'
    check "container(s) crash-looping or failing to start" \
      'kube_pod_container_status_waiting_reason{reason=~"CrashLoopBackOff|CreateContainerError|CreateContainerConfigError|ImagePullBackOff|ErrImagePull"} == 1'
    check "Running pod(s) not Ready" \
      '(kube_pod_status_ready{condition="false"} == 1) and on(namespace, pod) (kube_pod_status_phase{phase="Running"} == 1)'
  fi
fi

if [ ${#reasons[@]} -gt 0 ]; then
  summary="Reboot of $NODE held: $(printf '%s; ' "${reasons[@]}" | sed 's/; $//'). Kernel/security update stays inactive; retried at the same slot tomorrow."
  log "$summary"
  if [ "$DRY_RUN" = 1 ]; then echo "DRY RUN: would hold and post NodeRebootHeld"; exit 0; fi
  # 26h: still firing when tomorrow's run re-posts or resolves it.
  post_alert "$(date -u -d '+26 hours' +%Y-%m-%dT%H:%M:%SZ)" "$summary" \
    || log "could not post NodeRebootHeld to Alertmanager (${AM:-unresolved})"
  exit 1
fi

log "cluster healthy, rebooting $NODE for: $(cat /run/reboot-required.pkgs 2>/dev/null | tr "\n" " ")"
if [ "$DRY_RUN" = 1 ]; then echo "DRY RUN: would resolve NodeRebootHeld and reboot"; exit 0; fi
post_alert "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "Reboot of $NODE no longer held" || true
systemctl reboot
