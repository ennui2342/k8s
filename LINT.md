# Cluster Hygiene Checklist

The explicit, mechanically-checkable standard for manifests in this repo — the k8s-repo
equivalent of a linter's rule set. **Not auto-loaded into every session's context** (unlike
`CLAUDE.md`) precisely so it can grow without taxing every unrelated conversation — it's
consulted explicitly, at specific checkpoints:

- The periodic fleet audit (`~/projects/agents/k8s/fleet-audit-prompt.md`) walks this file
  exhaustively against every matching manifest, every run.
- The nightly upgrade specialist (`~/projects/agents/k8s/upgrade-prompt.md`) checks any
  manifest it writes or edits against this file before committing.
- Any session (automated or interactive) about to write or edit a manifest should check it too —
  `CLAUDE.md` points here for exactly that reason.

This list starts short and is meant to grow: when the audit's research pass, the upgrade
specialist, or anyone in any session finds a new durable best practice worth enforcing
repo-wide, it gets added here as a new checkable rule — not left in a task or a Discord message.
A finding that isn't captured here doesn't survive past the run that found it — see
`feedback_boyscout_or_ticket` in this machine's memory for why that distinction matters.

## Confirmed rules

**Every CronJob must set `ttlSecondsAfterFinished`.** Confirmed live 2026-07-28: 6 of the 7
CronJobs in this repo had no `ttlSecondsAfterFinished` (only `syncthing/cronjob.yaml` did), so
completed Job pods never got cleaned up on their own. This isn't just tidiness —
`trivy/trivy.yaml`'s CronJob mounts a real RWO PVC (`trivy-cache-pvc`), and stale completed pods
from it ended up pinning that PVC and blocking a later run, caught mid-way through a nightly
automated update rather than by design. Every `CronJob.spec.jobTemplate.spec` (sibling of
`template:`, not inside it) must set it.

**Value depends on the schedule frequency:**

- **Daily or less frequent** (weekly/monthly — `trivy`, `isfdb-refresh`, `os-eol-scanner`,
  `syncthing`): `ttlSecondsAfterFinished: 604800` (7 days) — long enough to inspect a failed
  run's logs before it's swept, short enough that pods don't accumulate indefinitely.
- **Sub-daily** (every few hours or less — `nas-diskio-monitor` `*/5`, `nas-monitor` `*/15`,
  `health-monitor` `*/30`, `linkding-task-sync` `*/30`, `pvc-usage-monitor` `0 */2`):
  `ttlSecondsAfterFinished: 3600` (1 hour). Confirmed live 2026-08-26 and again 2026-08-28 (tm
  tasks around `50cad5c2` / `d88f06c9`): with a 7-day TTL, a *single* transient failure (one slow
  SSH round-trip, one brief NAS/InfluxDB blip) leaves a Failed Job object sitting for the full
  week, and `KubeJobFailed` keeps firing that entire time even though every subsequent run — 180
  to 1000+ of them — succeeds. `failedJobsHistoryLimit` (default 1) does *not* help here: a later
  *successful* run doesn't evict the failed Job, only its TTL does. At 3600s an isolated blip
  self-clears within the hour, while a genuinely persistent failure still re-alerts via fresh
  Failed Jobs on the next scheduled run. Only safe because none of these sub-daily jobs mount an
  RWO PVC — the `trivy` PVC-pinning failure mode that motivated this rule can't occur when the
  only volumes are ConfigMaps/Secrets. A sub-daily CronJob that *does* mount an RWO PVC should
  keep 604800 and instead lengthen its schedule or fix the failure at the source.

`successfulJobsHistoryLimit`/`failedJobsHistoryLimit` (k8s defaults: 3/1) are a different,
complementary mechanism — they cap how many Job *objects* are kept, not when the underlying pod's
resources (including PVC mounts) actually get released.

**Every container in a Deployment/StatefulSet/DaemonSet should set resource `requests`/`limits`.**
Audited repo-wide 2026-07-29 (first fleet-audit run): 21 containers across 19 manifests had no
`resources.requests`/`resources.limits` at all — `mosquitto/mosquitto`, `syncthing/syncthing`,
`modpoll/modpoll`, `wallabag/wallabag`, `librarium-db/postgres`,
`nfs-subdir-external-provisioner/nfs-subdir-external-provisioner`, `web/nginx`, `web/php`,
`freshrss/freshrss`, both `mdns-repeater` containers plus the worker's `setup` initContainer,
`homeassistant/homeassistant`, `registry/registry`, `webdav/webdav`, `influxdb/influxdb`,
`telegraf/telegraf`, `node-exporter/node-exporter`, taskmgt's `api`/`frontend`,
`ring-mqtt/ring-mqtt`, and `linkding/linkding`. Not fixed directly this run — sizing 21 diverse
containers on a resource-constrained Pi cluster is a judgement call, not a copy-paste fix — see
`tm` task `c6e594d0` (batched, `#~upgrade`). The established pattern already used by
`librarium/api-deployment.yaml`, `librarium/web-deployment.yaml`, and
`isfdb/adapter-deployment.yaml`/`isfdb/mariadb-statefulset.yaml`: set a `cpu` **request** only (no
`cpu` limit, to avoid throttling) plus a `memory` **request and limit**, sized from real usage
(`kubectl top pod --containers`), not guessed. Re-audited 2026-08-15: one more container found
missing resources entirely, `opsimath/worker-deployment.yaml`'s `wait-for-schema` initContainer
(opsimath postdates the original 2026-07-29 sweep) — folded into `c6e594d0` rather than a new
ticket. **Check-method caveat found the same day:** `flux-system/gotk-patches.yaml` looks like a
violation on a naive per-file scan but isn't — it's a strategic-merge `Deployment` patch (only
overrides the SOPS env var/volume mount), not a full pod spec, and the container it patches
(`kustomize-controller`/`manager`) already has `resources` set in the base
`flux-system/gotk-components.yaml`. Any future per-container scan (this rule, or the probes rule
below) must diff against the *merged* spec for patch files like this one, not flag the patch file
in isolation.

**No orphaned PVCs** (Bound, but no owning workload *and* no manifest reference anywhere in this
repo). Audited repo-wide 2026-07-29: every Bound PVC was cross-checked against every manifest in
the repo (StatefulSet `volumeClaimTemplates`-derived PVCs verified against their owning
StatefulSet, not just grepped by name). Found `default/resiliosync-config-pvc` and
`default/resiliosync-data-pvc` — 1Gi each, `Retain` reclaim policy, created 2023-03-14, zero
references anywhere in the repo — leftover from Resilio Sync, which `syncthing/` replaced (commit
`a2b244a`) over three years ago. This is exactly the openhab situation from 2026-07-28 (commit
`d48bb1d`), caught reactively by a usage alert rather than proactively — which is why this rule
exists. Not deleted directly this run: PVC/PV deletion is a data-deletion decision, ticketed
instead as `tm` task `776f5af9` (untagged, human-review-only). Check method for future audits:
`kubectl get pvc -A -o json`, then for each Bound PVC not generated by a StatefulSet
`volumeClaimTemplate`, grep the repo for its name — zero hits means orphaned.

**Every `imagePullPolicy: Never` entry should have an explicit comment explaining why** it's on
that pattern instead of the local registry (`registry/`, `127.0.0.1:30500`). Audited repo-wide
2026-07-29: **zero** manifests in the repo use `imagePullPolicy: Never` — every custom/forked
image (`mdns-repeater`, `isfdb-mirror`, `librarium-api`/`librarium-web`, `mosquitto`, `modpoll`,
`home-assistant`, `telegraf`, `ring-mqtt`, `trivy`, `botkube`, the Flux controllers,
`k8s-toolbox`) has fully migrated to the local registry with `imagePullPolicy: IfNotPresent`.
CLAUDE.md's per-service notes and the `registry/` row were stale (still described several of
these as `ghcr.io/...`/`imagePullPolicy: Never`) and were corrected this run. Rule kept active as
a regression guard, not because there's currently anything to fix — if a future manifest
reintroduces `Never` without a comment, that's the violation to catch.

**Every top-level app directory in the root `kustomization.yaml` must be documented in
`CLAUDE.md`**: a row in Actively Deployed Services, its ingress hostname(s) (if any) in Key
Ingress Hostnames, its `*-secret.yaml` file(s) (if any) in Secrets Management, and an entry in
Directory Structure Notes. Found live 2026-07-29 (first fleet-audit run): `freshrss/`, `linkding/`,
and `wallabag/` — three fully-deployed, actively-running services (added 2026-07-24, per commits
`7e62573`/`ee04d6a`) — were completely absent from all four of those CLAUDE.md sections, and
`botkube/`'s secret (`botkube-secret.yaml`) and Directory Structure Notes entry were missing too
despite the service itself having a table row. This violates GitOps Principle 4 ("this directory
must be sufficient to rebuild the cluster from scratch") — an undocumented namespace doesn't get
rebuilt from reading CLAUDE.md alone. Fixed directly this run (pure additive documentation, no
manifest risk). Check method for future audits: diff the directory list in root
`kustomization.yaml`'s `resources:` against the namespace column of CLAUDE.md's Actively Deployed
Services table, and diff `find . -name '*-secret.yaml'` against CLAUDE.md's Secrets Management
list. Re-exercised 2026-09-01: `nas-diskio-monitor/` (added 2026-08-23, tm task `50cad5c2`) was
live and in the root `kustomization.yaml` but absent from the Actively Deployed Services table,
the Secrets Management list (its own `nas-diskio-ssh-key` secret), and Directory Structure Notes —
same class as the freshrss/linkding/wallabag gap. Fixed directly (commit `a79c3e6`). Also found
the same run: the Directory Structure Notes line for `home-assistant/` still listed a "cleanup
CronJob" that no longer exists in the manifests — corrected in the same commit.

**The cluster's k3s / Kubernetes control-plane version must not be past upstream End of Life.**
New rule 2026-09-01 (Phase 2 research pass). Check method: `kubectl get nodes -o
jsonpath='{.items[0].status.nodeInfo.kubeletVersion}'` gives the k3s/k8s version (e.g.
`v1.32.13+k3s1`); cross-check the `1.MINOR` line against the Kubernetes release support window
(`https://kubernetes.io/releases/` — each minor gets ~14 months, roughly 12 months of patches +
2 months maintenance). Found live 2026-09-01: the fleet runs `v1.32.13+k3s1`, and Kubernetes
1.32 reached upstream EOL on **2026-02-28** (v1.32.13 being its final patch) — so the control
plane had been running an EOL, no-further-security-fixes k8s version for ~6 months with nothing
in this checklist prompting the check. This is the control-plane analogue of the host-OS EOL gap
that `os-eol-scanner/` was built to close (`tm` task `b914610a`), and of the
`ttlSecondsAfterFinished` gap — a slow-moving liability that no single CVE task surfaces as
"you are unsupported." Not a mechanical fix — a k3s minor-version jump crosses every node and
needs a human-scheduled window. Already tracked as `tm` task `24344397` (`§wait`,
`~k3s-upgrade`, `!1`, `+cli.claude-code.k8s`) — that task's assignee was also added this run
(it was ownerless/orchestrator-invisible). Future audits: if this task is still open/wait and
the running version is still EOL, note it in the report; if it's been closed but the version is
still EOL, that's a new finding.

**Every Deployment/StatefulSet/DaemonSet must include the soft worker-preference node affinity**
from CLAUDE.md's Scheduling Constraints section (or, for a DaemonSet that must run on every node
including the master, the documented toleration — or a *stricter* hard
`requiredDuringSchedulingIgnoredDuringExecution` exclusion of the control-plane role, which
satisfies the same intent). Audited repo-wide 2026-07-29 (first time this pre-existing CLAUDE.md
rule has actually been checked mechanically): full compliance across every
Deployment/StatefulSet/DaemonSet in the repo. `mdns/worker-daemonset.yaml` uses a hard `required`
control-plane exclusion rather than the literal soft-preference block, which is stricter than the
rule asks for and was treated as compliant, not a violation. No fix or ticket needed — recorded
here so the next audit doesn't have to re-derive the check from prose. Re-checked 2026-08-15:
`flux-system/gotk-components.yaml`/`gotk-patches.yaml` (the Flux bootstrap controllers themselves
— `helm-controller`, `image-automation-controller`, `image-reflector-controller`,
`kustomize-controller`, `notification-controller`, `source-controller`) have no affinity or
toleration and were checked but are **not** a violation: CLAUDE.md's Scheduling Constraints rule
is explicitly scoped to "**user workloads**", and these are Flux's own auto-generated bootstrap
manifests (`CLAUDE.md`: "do not edit manually"), not something this repo authors. They also
physically cannot land on the control plane regardless — the control-plane taint alone blocks any
pod lacking an explicit toleration, which none of these set. Recorded here so a future audit
doesn't re-flag `flux-system/` as an affinity gap.

**Every `Ingress` must set `spec.ingressClassName`, never the deprecated
`kubernetes.io/ingress.class` annotation.** Found and fixed repo-wide 2026-07-29 (Phase 2 research
pass): 10 `Ingress` objects across 9 manifests, plus the Grafana ingress values in
`prometheus/helmrelease.yaml`, still used the long-deprecated annotation instead of the field —
this repo already used the modern field consistently for every Tailscale-backed ingress
(`ingressClassName: tailscale`), so these were pure stragglers. Same-behavior swap (Traefik treats
both identically), fixed directly rather than ticketed.

**Namespaces that run privileged/`hostNetwork` workloads should be a conscious, documented
exception, not a default.** Checked live 2026-07-29 (Phase 2 research pass): only
`mdns/master-daemonset.yaml` and `mdns/worker-daemonset.yaml` (both `default` namespace) set
`privileged: true`/`hostNetwork: true` anywhere in the repo — CLAUDE.md's home-assistant row
incorrectly claimed `hostNetwork` too (corrected same run). Re-checked 2026-09-01:
`mdns/master-daemonset.yaml` was removed 2026-08-22 in the flat-network migration, so
`mdns/worker-daemonset.yaml` is now the *only* privileged/`hostNetwork` workload in the repo —
still `default` namespace, still the documented mDNS-relay exception. Whether to formally adopt Pod Security
Admission (`pod-security.kubernetes.io/enforce` namespace labels — the GA replacement for the
long-removed PodSecurityPolicy) to make this an enforced boundary rather than an implicit one is a
security-posture decision, not a mechanical fix: ticketed as `tm` task `403129f3` (untagged, human-review-only)
rather than adopted directly, since this is a trusted single-tenant homelab and blast-radius
tradeoffs need a human call, not a default-on assumption.

**Every container in a Deployment/StatefulSet/DaemonSet should set a `readinessProbe` and/or
`livenessProbe`.** Audited repo-wide 2026-08-15 (Phase 2 research pass, new rule this run): 17 of
36 live containers had neither probe set at all — `freshrss/freshrss`,
`home-assistant/ha-deployment.yaml`'s `homeassistant`, `linkding/linkding`, both `mdns-repeater`
containers, `monitoring/node-exporter.yaml`'s `node-exporter`, `monitoring/telegraf.yaml`'s
`telegraf`, `mosquitto/mosquitto`, `nfs/template.yaml`'s `nfs-subdir-external-provisioner`,
`opsimath/worker-deployment.yaml`'s `opsimath-worker`, `ring-mqtt/ring-mqtt`,
`solar/modpoll.yaml`'s `modpoll`, `syncthing/syncthing`, `wallabag/wallabag`, `webdav/webdav`,
and both `website/nginx.yaml` containers (`nginx`, `php`). Without either probe, k8s has no signal
that a hung-but-running container should be restarted (no liveness) or pulled out of Service
rotation (no readiness) — confirmed as a real gap on roughly half the fleet's workloads, not
hypothetical. Not fixed directly this run: probe design is per-workload (HTTP app vs. MQTT broker
vs. Modbus poller vs. UDP relay share no common shape), the same judgement-call class as the
resources rule above — ticketed as `tm` task `cb71bb32` (batched, `#~upgrade`). The established
pattern already used by `isfdb-adapter`, `librarium-api`/`librarium-web`,
`opsimath-web`/`opsimath-cover-compare`, `taskmgt` `api`/`frontend`, `registry`, `influxdb`, and
the `flux-system` controllers themselves: `httpGet` against the app's own health endpoint for HTTP
services; `librarium-db/postgres`, `isfdb-db/mariadb`, `opsimath-db/postgres` use `exec`
(`pg_isready`/equivalent) for DB StatefulSets. Same check-method caveat as the resources rule:
`flux-system/gotk-patches.yaml`'s `kustomize-controller` looks like a violation on a naive scan
but isn't — its probes are already set in the base `gotk-components.yaml`.

## Starter items — not yet verified repo-wide

Empty as of 2026-09-01. The next durable finding (from a future audit's research pass, or from
any session) seeds this list again. (2026-09-01 audit: the one Phase 2 finding — control-plane
EOL — was concrete enough to go straight into "Confirmed rules" rather than land here first.)
