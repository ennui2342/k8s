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
in isolation. Re-checked 2026-09-15 (restricted to `git ls-files` — i.e. tracked, live manifests
only, excluding the `.gitignore`d inactive experiments under `nfs/old/`, `resilosync/`,
`magic-mirror/`, `home-assistant/src/templates/`, `indi-allsky/`): still exactly the same 21
containers across the same 19 manifests as 2026-08-15 — no drift, `tm` task `c6e594d0` still
accurate as filed. Re-checked 2026-10-01: still 21 containers / 19 manifests (19 regular + the
`mdns` `setup` and opsimath `wait-for-schema` initContainers) — but note the *composition* has
shifted from the original list: `librarium-db/postgres` and the master `mdns-repeater` are gone
(both removed 2026-08-22), so the `librarium/*` files cited above as the "established pattern"
no longer exist — use `isfdb/adapter-deployment.yaml`/`isfdb/mariadb-statefulset.yaml` or
`opsimath/` as the reference instead. Task `c6e594d0` (`§wait`, now correctly untagged) still
covers the gap. Re-checked 2026-10-15: same 21 containers / 19 manifests, no drift. Re-checked 2026-11-01: **20
containers / 18 manifests**. `nfs-subdir-external-provisioner` was fixed (`aa2a930`), the unreferenced
`monitoring/node-exporter.yaml` was deleted, and `system-upgrade-controller` is new (vendored in
`system-upgrade/upstream/`, so its fix belongs in that directory's kustomize patches). Noted on `c6e594d0`.

**No orphaned PVCs** (Bound, but no owning workload *and* no manifest reference anywhere in this
repo). Audited repo-wide 2026-07-29: every Bound PVC was cross-checked against every manifest in
the repo (StatefulSet `volumeClaimTemplates`-derived PVCs verified against their owning
StatefulSet, not just grepped by name). Found `default/resiliosync-config-pvc` and
`default/resiliosync-data-pvc` — 1Gi each, `Retain` reclaim policy, created 2023-03-14, zero
references anywhere in the repo — leftover from Resilio Sync, which `syncthing/` replaced (commit
`a2b244a`) over three years ago. This is exactly the openhab situation from 2026-07-28 (commit
`d48bb1d`), caught reactively by a usage alert rather than proactively — which is why this rule
exists. Not deleted directly this run: PVC/PV deletion is a data-deletion decision, ticketed
instead as `tm` task `776f5af9` (untagged, human-review-only). Re-checked 2026-09-15: both PVCs
still Bound, still unreferenced, task `776f5af9` still open — no change. Check method for future audits:
`kubectl get pvc -A -o json`, then for each Bound PVC not generated by a StatefulSet
`volumeClaimTemplate`, grep the repo for its name — zero hits means orphaned. **Check-method
caveat found 2026-09-15:** this flagged
`monitoring/prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0`
as a false positive — it's generated dynamically by the Prometheus Operator from the `Prometheus`
CR's own `volumeClaimTemplate` (not a StatefulSet this repo authors directly), so it has no
`ownerReferences` a naive check recognizes and no literal name match in any manifest, yet is
actively Bound to a `Running` pod. Before treating a no-owner, no-name-match PVC as orphaned,
confirm no `Running` pod currently has it mounted (`kubectl get pod -A -o json` cross-referenced
by volume claim name) — a live mount means "operator-managed", not "orphaned", regardless of what
grep finds. Re-checked 2026-10-15 and 2026-11-01: only the two `resiliosync-*` PVCs flagged, `776f5af9` still open.

**Every `imagePullPolicy: Never` entry should have an explicit comment explaining why** it's on
that pattern instead of the local registry (`registry/`, `127.0.0.1:30500`). Audited repo-wide
2026-07-29: **zero** manifests in the repo use `imagePullPolicy: Never` — every custom/forked
image (`mdns-repeater`, `isfdb-mirror`, `librarium-api`/`librarium-web` (since removed), `mosquitto`, `modpoll`,
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
same class as the freshrss/linkding/wallabag gap. Fixed directly (commit `d32243f`). Also found
the same run: the Directory Structure Notes line for `home-assistant/` still listed a "cleanup
CronJob" that no longer exists in the manifests — corrected in the same commit.

**Check method changed 2026-10-01:** the root `kustomization.yaml` no longer lists app directories
at all — since the per-app Flux Kustomization cutover (tm `9db56d2e`) it holds only
`flux-system/` + `kustomizations/`. The authoritative app list is now
`kustomizations/kustomization.yaml`'s `resources:` (one `kustomizations/<app>.yaml` per app, each
with `path: ./<app>`) — diff *that* against CLAUDE.md. Re-checked 2026-10-01 against all 31
per-app Kustomizations: every one appears in Directory Structure Notes, and every tracked
`*-secret.yaml` (15) is in Secrets Management. `coredns/`, `dashboards/`, and `traefik/` have no
Actively Deployed Services row, which is **not** a violation: they're config-only directories (a
CoreDNS override ConfigMap, Grafana dashboard ConfigMaps, a k3s `HelmChartConfig`) with no
workload of their own, and are documented in Directory Structure Notes (and Traefik
Customization) instead.

**The reverse direction is checked too: `CLAUDE.md` and `RUNBOOK.md` must not carry live
instructions for app directories that no longer exist.** Found 2026-10-01: `librarium/` was
removed from the repo and cluster 2026-08-22 (deleted inside the unrelated commit `852a6fe`),
but `RUNBOOK.md` still had two full sections ("Librarium" and "Librarium local fork images")
walking a from-scratch rebuild through five manifests that no longer existed. CLAUDE.md's own
mentions were already phrased as history ("permanently removed … see git history") and are fine.
Fixed directly (commit `3245c82`). Check method: extract every backticked `<dir>/…` path from
both files (regex `[a-z0-9-]+/[A-Za-z0-9._/-]*` between backticks) and flag any whose top-level directory
doesn't exist in `git ls-files`. Most hits are false positives: in-cluster `namespace/name`
references, GitHub `owner/repo` slugs, and non-repo paths like `config/master.key`. Only a
missing *app directory* that's described as current state is a violation.

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
still EOL, that's a new finding. Re-checked 2026-09-15: still `v1.32.13+k3s1`, still EOL, task
`24344397` still `§wait` — no change, noted in report only. Re-checked 2026-10-01: same — all
four nodes `v1.32.13+k3s1`, `24344397` still `§wait`. Re-checked 2026-10-15: same. The v1.33–v1.36
removals (gitRepo volumes, kube-proxy IPVS mode, Service `externalIPs`, v1 `Endpoints`, and k3s's
Traefik chart v40 `kubernetesIngressNginx` provider rename) were checked against the repo, and none
apply. Recorded as a note on `24344397`. Nodes now run Ubuntu 26.04 / kernel 7.0
(cgroup v2 by default) with containerd 2.1.5, so the cgroup-v1/containerd-1.x removals in recent
k8s minors shouldn't block the jump. See the deprecated-API rule below for the other pre-upgrade
check. **Resolved 2026-10-24:** upgraded v1.32.13 → v1.33.13 → v1.34.12 → v1.35.9 → **v1.36.5+k3s1** via system-upgrade-controller (Kubernetes 1.36 EOL 2027-06-28), `24344397` closed. The declared version now lives in `k3s-upgrade/plans.yaml`; check that file *and* `kubectl get nodes` against endoflife.date. Re-checked 2026-11-01: compliant. v1.36.5+k3s1 is still k3s's `stable` channel; 1.37 is out, but there's no EOL pressure yet.

**Every app namespace should have an explicit answer on network segmentation, even if the answer
is "not yet."** New rule 2026-09-15 (Phase 2 research pass). Check method: `git grep -l "kind:
NetworkPolicy"` — anything other than `flux-system/gotk-components.yaml` (Flux's own
bootstrap-managed policy) means an app namespace has one. Found live 2026-09-15: zero
`NetworkPolicy` objects exist for any app namespace — Kubernetes networking is fully open by
default fleet-wide, any pod can reach any other pod/Service across every namespace. Not a
mechanical fix: a default-deny policy risks breaking real cross-namespace traffic this fleet
relies on (Prometheus scraping every namespace, `epigone`'s cross-namespace IngressRoute to
`home-assistant`, `opsimath`→`isfdb-adapter`) unless carefully scoped first, and this is a trusted
single-tenant homelab, not the multi-tenant environment NetworkPolicy mainly protects — same class
of security-posture judgement call as Pod Security Admission above. Ticketed as `tm` task
`eba39725` (untagged, human-review-only, `+cli.claude-code.k8s`) rather than adopted directly.
Future audits: if this task is still open and still zero NetworkPolicies exist, note it in the
report; if it's been closed but the gap is unaddressed, that's worth a fresh look. Re-checked
2026-10-01, 2026-10-15 and 2026-11-01: still only Flux's three bootstrap policies, `eba39725` still open. No change.

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
both identically), fixed directly rather than ticketed. **Check-method caveat found 2026-09-15:**
a naive `grep -rl "kind: Ingress"` also matches `kind: IngressRoute` (Traefik's own CRD,
`traefik.io/v1alpha1`, used by `epigone/ingressroute.yaml`) — that object type has no
`ingressClassName` field at all (routing is implicit via `entryPoints`, not an ingress class), so
it is not a violation. Match on `^kind: Ingress$` (exact line), not a substring, in future audits.

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
tradeoffs need a human call, not a default-on assumption. **Scope caveat found 2026-11-01:** a repo
scan only sees what the repo authors. Check live too (`kubectl get pod -A -o json`, filter on
`hostNetwork` and `securityContext.privileged`). Live, the other exceptions are chart- and
operator-generated: `tailscale/ts-k8s-connector-*` (privileged), the kube-prometheus-stack
node-exporter (`hostNetwork`), and the k3s-upgrade Plan Jobs (privileged by design, see CLAUDE.md). All
expected; `mdns/worker-daemonset.yaml` is still the only repo-authored one.

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
but isn't — its probes are already set in the base `gotk-components.yaml`. **Second check-method
caveat found 2026-09-15:** init containers (e.g. `opsimath/worker-deployment.yaml`'s
`wait-for-schema`) should not be flagged by this rule — they run to completion and exit, so
neither `readinessProbe` nor `livenessProbe` is meaningful for them; only the resources rule above
applies to init containers, not this one. Re-checked 2026-09-15 (tracked files only, init
containers excluded): still exactly the same 17 containers across 16 manifests as 2026-08-15 — no
drift, `tm` task `cb71bb32` still accurate as filed. **Corrected 2026-10-01:** the real count is
**16 containers across 15 manifests** — the 2026-09-15 re-check miscounted, since the master
`mdns-repeater` (one of the original 17) was removed 2026-08-22 with `mdns/master-daemonset.yaml`.
No new violations; `cb71bb32` covers the remaining 16 (its "17/16" title is one stale). Same
`librarium-*` caveat as the resources rule: those reference manifests no longer exist.
Re-checked 2026-10-15: same 16 / 15, no drift. Re-checked 2026-11-01: still 16 / 15, but the
composition changed: `node-exporter` went (manifest deleted, it was never deployed) and
`system-upgrade-controller` came in. Noted on `cb71bb32`.

**No manifest may use a deprecated API version, and the live apiserver must report no
deprecated-API traffic.** New rule 2026-10-01 (Phase 2 pass). Currently fully compliant, so it's
kept as a regression guard. It matters most right before the pending k3s
1.32 → 1.36 jump (`tm` `24344397`), since anything still on a deprecated version at that point
risks becoming a removed one. Two halves, both mechanical:

1. **Live traffic:** `kubectl get --raw /metrics | grep '^apiserver_requested_deprecated_apis'`
   must print nothing. Each series names the group/version/resource some client (a controller, a
   Helm chart, or a manifest Flux applies) is still calling. Checked 2026-10-01: zero series.
2. **CRD versions in the repo:** list deprecated served versions with
   `kubectl get crd -o json | jq -r '.items[] | .metadata.name as $n | .spec.versions[] |
   select(.deprecated==true) | "\($n) \(.name)"'`, then confirm no tracked manifest uses any of
   them (`git ls-files '*.yaml' | xargs grep -h '^apiVersion:' | sort | uniq -c`). Checked
   2026-10-01: deprecated versions exist for the Flux `image.toolkit.fluxcd.io/v1beta2` and
   `notification.toolkit.fluxcd.io/v1beta2` kinds and the Gateway API `BackendTLSPolicy`
   `v1alpha3`. The repo uses only `image.toolkit.fluxcd.io/v1` and
   `notification.toolkit.fluxcd.io/v1beta3` (the current storage version for `Alert`/`Provider`),
   and no Gateway API objects. Compliant. Rechecked 2026-10-07, after the Flux v2.9.6 upgrade
   (`9f8a502`): the Flux `v1beta2` versions are gone from the CRDs entirely, and the only
   deprecated version left is `BackendTLSPolicy` `v1alpha3` (`served: false`). Rechecked
   2026-10-15: unchanged, and both halves are still clean. Rechecked 2026-11-01: halves 1 and 2 both
   changed, see below.

Fix for any future violation: bump the manifest's `apiVersion` to the CRD's current
`storage: true` version, checking the upstream migration notes for field renames first. This is
a single-manifest fix when the schema is unchanged; ticket it if fields moved. A hit in
half 1 that isn't explained by a repo manifest usually means a Helm chart or controller is too
old, which is upgrade-shaped work (`#~upgrade`).

**Half 1 is not literally "must print nothing" any more (2026-11-01).** The gauge means "requested at
least once since this apiserver started", and it never clears until k3s restarts, so a hit alone
proves nothing. Before acting, confirm the traffic is current:
`rate(apiserver_request_total{group=...,resource=...,version=...}[6h])` in Prometheus. Found
live 2026-11-01, three series:
- `endpoints` v1: deprecated in Kubernetes 1.33, with an empty `removed_release`. Not actionable by
  itself. Consumers include the Prometheus stack, whose upgrade is tracked in `1b232a78`. Ignore this
  series unless `removed_release` is ever set.
- `notification.toolkit.fluxcd.io` `alerts`/`providers` v1beta3: `APPLY`/`GET` stopped with the
  move to `v1` (`ad37bab`, 2026-10-28), which is what half 2 cares about. A low-rate `WATCH` on
  v1beta3 was still running on 2026-11-01 from a client not identified here (no apiserver audit
  log). Recorded on `4834c34f`, whose `storedVersions` cleanup is what retires v1beta3.

Half 2 on 2026-11-01: `alerts`/`providers` v1beta3 are now deprecated-but-served and every tracked
manifest uses `v1`, so it's compliant. The Gateway API deprecated versions are all `served: false`.

**No deployed image may use a floating/mutable tag.** New rule 2026-10-15 (closes `tm` task
`c479debe`). Every `image:` in a tracked manifest, and every image tag set in HelmRelease
values, must match `^v?[0-9]+\.[0-9]+(\.[0-9]+)*` (at least MAJOR.MINOR, tightened 2026-11-01, with
the full version where upstream publishes one; an optional `-patched`/`-lsNNN`-style suffix after the
numeric version is fine). `latest`, `latest-patched`, `debug`, `dev`, `local`, a bare
major (`registry:2`, `mariadb:11`), or a bare image with no tag are all violations. This is the global versioned-tag rule from the user's
`CLAUDE.md`, checked mechanically here. A floating tag defeats the reconcile-scanner's
version comparison (`trivy/patched-images.yaml` `upstream_image`; `discover.sh` skips unparseable
tags) and hides what's actually deployed. It also lets an `IfNotPresent` node cache silently
serve a stale image (see `f38e4a07`). How `crane:debug` went unnoticed in `trivy/trivy.yaml`
until a CVE flagged it (fixed `cebac68`) is why this rule exists. Check method:
`git grep -n -E 'image: ' -- '*.yaml' ':!flux-system/gotk-components.yaml'` and flag any tag that
isn't numeric. Strip the registry host's `:30500` port before matching, since a naive
`:[0-9]+` regex wrongly passes `127.0.0.1:30500/foo:latest-patched`. Also cross-check live with
`kubectl get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | sort -u`.
Exempt: `ImageRepository.spec.image` in `flux-system/*-image-automation.yaml` (a repo to watch,
not a deployed tag), and `upstream_image` entries in `trivy/patched-images.yaml` (tracked per-fork
under the tasks below). Found live 2026-10-15:
- `webdav/deployment.yaml`: `ghcr.io/hacdias/webdav:latest`. Fixed directly by pinning to
  `v5.16.0`, the tag whose digest (`sha256:fcde257b…`) matched the running pod exactly, so
  there's no behaviour change. Note that `:latest` had already moved on to v5.17.1 upstream. Any
  bump past v5.16.0 is a separate, deliberate upgrade.
- `mdns/worker-daemonset.yaml`: `127.0.0.1:30500/mdns-repeater:latest-patched`. Already
  ticketed as `f9bd4e02`.
- `ring-mqtt/ring-mqtt.yaml`: `127.0.0.1:30500/ring-mqtt:latest-patched`. Already ticketed as
  `6892ffca`.

Re-checked 2026-11-01 (tm `bfb9d647`, found by the upgrade specialist): upstream retags a bare major
on every release, so it's as mutable as `latest`, and the old regex passed it.
- `isfdb/mariadb-statefulset.yaml`: `mariadb:11`. Pinned to `11.8.9`, the running version. No tag's
  digest matched the running pod (`sha256:2439dcd7…` is an older build of 11.8.9), so the rollout
  also picked up upstream's current 11.8.9 rebuild.
- `registry/deployment.yaml`: `registry:2`. Tracked in `092fd102`, which replaces its EOL base.
- `mdns-repeater` and `ring-mqtt` `latest-patched`: unchanged, still `f9bd4e02` and `6892ffca`.

The fix for a third-party image is to pin to the version tag whose digest matches what's
currently running (compare `kubectl get pod … -o jsonpath='{..imageID}'` against the registry's
`Docker-Content-Digest` per tag). For a locally built fork, rebuild and push under a versioned tag
(`<upstream-ver>-patched`), then update both the manifest and `trivy/patched-images.yaml`.

**Every tracked manifest must be reachable from a Flux Kustomization.** New rule 2026-11-01. A
`*.yaml` file that no `kustomization.yaml` includes is never applied, but it still reads as live
config and pollutes every scan. Found live: `monitoring/node-exporter.yaml`, a whole DaemonSet that
wasn't in `monitoring/kustomization.yaml` and wasn't running (the live node-exporter comes from
kube-prometheus-stack). It had been counted in the resources and probes rules since they were
written, and it was the one affinity-rule hit this run. Deleted directly, it's in git history.
Check method: walk `resources`/`patches`/`components` from each `kustomizations/*.yaml`
`spec.path`, then diff against `git ls-files '*.yaml'`. Expected leftovers: `.sops.yaml` and
`trivy/patched-images.yaml` (a `configMapGenerator` input, not a manifest). Inactive manifests
belong in `.gitignore` (GitOps Principle 5), not tracked.

**Every `127.0.0.1:30500/...` image in use must actually exist in the registry.** New rule
2026-11-01. The local-registry tag is pulled with `IfNotPresent`, so a running pod proves nothing: a
node's containerd cache hides a missing image until a pod lands on a node without it. Found live:
`127.0.0.1:30500/botkube:v1.14.0-patched` returned 404, most likely lost in the 2026-09-06 prune
recovery (not confirmed). It was cached on `k8s-1`/`k8s-3` only, so a reschedule to `k8s-2` would
have hit `ImagePullBackOff`. Fixed directly by pushing the Mac's cached copy after confirming that its
layers and build time matched the node image, then pulling it on `k8s-2`. Check method: collect every
`127.0.0.1:30500/` image from live pods, workload specs, and tracked manifests (including HelmRelease
`registry`/`repository`/`tag` values), then `curl` each
`http://192.168.0.81:30500/v2/<name>/manifests/<tag>` with OCI index, Docker manifest-list, and v2
`Accept` headers. Anything but 200 is a violation. Rebuild from `trivy/patched-images/<name>/` if
no cached copy exists. Compare diff IDs, not image IDs: Docker Desktop's ID differs from
containerd's for the same image.

**`trivy/patched-images.yaml` `patched_image` must equal the image actually deployed.** New rule
2026-11-01. `trivy/trivy.yaml` keys forks on this exact string (`patched_by_image`), so a stale value
makes the fork invisible to fork-aware scanning. Found live: `ring-mqtt` and `botkube` still said
`ghcr.io/ennui2342/...` from before the registry migration. Both fixed directly. Check method:
every `patched_image` must appear in a tracked manifest or a HelmRelease image value. `influxdb:1.8.0`
is a tracked non-fork entry and passes.

**Exec probes on NFS-backed databases must set `timeoutSeconds`, never the 1s default.** New rule
2026-11-01 (from `e8934151`). An exec probe that spawns a client on a Pi-class node over NFS can
exceed 1s under ordinary latency, and a timed-out liveness probe restarts the database. That happened
to `librarium-db` (51 restarts) and is why `opsimath-db` uses 15s. Found live:
`isfdb/mariadb-statefulset.yaml` had both probes on the default. Fixed directly (`timeoutSeconds:
15`, matching `opsimath/postgres.yaml`). Check method: list every `exec` probe in a
Deployment/StatefulSet, flag any with `timeoutSeconds` unset or below 5.

**The Mac kubeconfig's client certificate must have more than 60 days left.** New rule 2026-11-01
(Phase 2 pass). Certificate expiry isn't a manifest property, but this one takes out every
automated specialist at once. Found live: `/Volumes/SSD/sync/secure/kubeconfig` embeds the k3s
`system:admin` cert, which expires 2027-03-09, and nothing tracked that. k3s renews its own leaf
certs on restart, but that doesn't update the Mac's copy. Check method: `kubectl config view --raw
--minify -o jsonpath='{.users[0].user.client-certificate-data}' | base64 -d | openssl x509 -noout
-enddate`. Ticketed as `tm` task `9da1734f`.

## Starter items — not yet verified repo-wide

Empty as of 2026-11-01 (unchanged since 2026-09-01; the floating-tag rule and this run's five new rules were concrete enough to go straight into Confirmed rules). The next durable finding (from a future audit's research pass, or from
any session) seeds this list again. (2026-09-01 audit: the one Phase 2 finding — control-plane
EOL — was concrete enough to go straight into "Confirmed rules" rather than land here first.)
