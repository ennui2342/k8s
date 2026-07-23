# k8s Fleet Repository

This is the GitOps source of truth for the homelab Kubernetes cluster at `k8s.local`.
All active app manifests live here. Flux reconciles the cluster against this repo.

## Cluster Topology

- **k3s** v1.32
- **Master** (`k8s`, `ubuntu@k8s.local`): control plane only — tainted `node-role.kubernetes.io/control-plane:NoSchedule`. Directly accessible from dev Mac via SSH and kubeconfig.
- **Workers**: `k8s-1` (`ubuntu@k8s-1`), `k8s-2` (`ubuntu@k8s-2`) — reachable from master only (SSH keys on master)
- **Ingress**: Traefik v3 (bundled with k3s)
- **Storage**: NFS StorageClass `nfs-client` backed by `192.168.0.76:/mnt/md0/k8s` (all PVs are NFS — no local disk dependency)
- **VPN**: Tailscale Kubernetes operator (namespace: `tailscale`)
- **TLS**: cert-manager with Let's Encrypt (ClusterIssuer: `letsencrypt-prod`). Note: `*.k8s.ecafe.org` is internal DNS only — do not attempt TLS for those hostnames.
- **GitOps**: Flux v2 pointing at `github.com/ennui2342/k8s` (branch: `main`)

## Scheduling Constraints

**These rules apply to every new workload added to this cluster.**

### Control plane is off-limits for user workloads
The master node (`k8s`) is tainted `node-role.kubernetes.io/control-plane:NoSchedule`. No user workload may run there. The k3s SQLite/kine datastore is sensitive to I/O and CPU latency — co-located workloads cause cascading failures (leader election loss, NodeNotReady events).

### All pod specs must include soft worker-preference affinity
Every Deployment, StatefulSet, and DaemonSet (user workloads) must include:

```yaml
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
            - key: node-role.kubernetes.io/control-plane
              operator: DoesNotExist
```

### DaemonSets that must run on all nodes
If a DaemonSet genuinely needs to run on the master (e.g. monitoring agents collecting control-plane metrics), it must explicitly tolerate the taint:

```yaml
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
```

## Actively Deployed Services

| Namespace | Service | Manifests | Notes |
|-----------|---------|-----------|-------|
| `botkube` | botkube | `botkube/` | Flux HelmRelease; Discord alerts + kubectl/helm/flux executors |
| `cert-manager` | cert-manager | `cert-manager/` | Flux HelmRelease (v1.x.x); ClusterIssuer for ecafe.org |
| `default` | mosquitto | `mosquitto/` | MQTT broker, anonymous access, port 31883 (NodePort) |
| `default` | mdns-repeater | `mdns/` | DaemonSets (master + worker) repeating mDNS packets across host interfaces so mDNS-discoverable devices are visible cluster-wide; `hostNetwork: true`, `privileged: true`; image `ghcr.io/ennui2342/mdns-repeater:latest-patched` (locally patched, imagePullPolicy Never) |
| `default` | modpoll | `solar/` | Reads FoxESS inverter via Modbus at 192.168.0.188, publishes to `solar/foxess` on MQTT |
| `default` | nfs-provisioner | `nfs/template.yaml` | NFS subdir external provisioner |
| `default` | syncthing | `syncthing/` | SyncThing file sync; config + data on NFS |
| `default` | webdav | `webdav/` | hacdias/webdav server for Zotero PDF attachment sync; 20Gi NFS PV; `webdav.k8s.ecafe.org` ingress (internal/Tailscale, used by desktop Zotero) plus a Tailscale-operator Funnel Ingress (`webdav-funnel`) giving a trusted `*.ts.net` cert that works identically on-LAN and off — needed because Zotero for Android refuses self-signed/internal certs and the epigone.ecafe.org path hit home-router NAT-hairpin issues when accessed from inside the LAN; basic-auth user `zotero`, bcrypt password in `webdav-secret.yaml` |
| `default` | web | `website/` | nginx + PHP-FPM StatefulSet; serves k8s.ecafe.org |
| `epigone` | epigone routing | `epigone/` | Owns the `epigone.ecafe.org` cert-manager Certificate + Traefik IngressRoute for Home Assistant. Kept as its own namespace (decoupled from home-assistant) since it was briefly shared with webdav too; webdav now uses Tailscale Funnel instead (see below), so this currently only fronts Home Assistant, but stays separate in case another service needs the same public hostname later. |
| `home-assistant` | homeassistant | `home-assistant/ha-*.yaml` | HA 2026.4.4, hostNetwork, config on NFS; reachable at `home-assistant.k8s.ecafe.org` and, via `epigone/`, at `epigone.ecafe.org` |
| `home-assistant` | ring-mqtt | `ring-mqtt/` | Ring doorbell → MQTT bridge, RTSP port 30002 |
| `monitoring` | cve-scanner | `trivy/` | Weekly Trivy scan → dedupes/files/auto-closes `tm` tasks; see CVE Patch Management below |
| `monitoring` | grafana | `prometheus/helmrelease.yaml` | grafana.k8s.ecafe.org, anonymous viewer access; managed by kube-prometheus-stack chart |
| `monitoring` | health-monitor | `health-monitor/` | CronJob: CrashLoopBackOff/failed-kustomization/NotReady-node checks → `tm` tasks |
| `monitoring` | influxdb | `monitoring/influxdb.yaml` | InfluxDB 1.8.0, 8Gi NFS PV |
| `monitoring` | kube-prometheus-stack | `prometheus/` | Flux HelmRelease (70.x.x); Prometheus + Alertmanager + Grafana + node-exporter + kube-state-metrics |
| `monitoring` | loki | `monitoring/loki.yaml` | Flux HelmRelease (6.x.x); log aggregation, 31-day retention, NFS storage |
| `monitoring` | promtail | `monitoring/promtail.yaml` | Flux HelmRelease (6.x.x); ships pod logs to Loki |
| `monitoring` | telegraf | `monitoring/telegraf.yaml` | Scrapes MQTT (mosquitto.default:1883), statsd, SNMP (NAS at 192.168.0.76) |
| `tailscale` | operator | `tailscale/` | Flux HelmRelease (1.x.x); `ts-k8s-connector` exposes taskmgt frontend; also runs the Funnel proxy for webdav (`ts-webdav-funnel` StatefulSet, auto-created from `webdav/funnel-ingress.yaml`) |
| `taskmgt` | api + frontend | `taskmgt/` | Task management app; see Flux image automation below |

### Key Ingress Hostnames
- `k8s.ecafe.org` — website
- `home-assistant.k8s.ecafe.org` — Home Assistant (internal DNS only)
- `epigone.ecafe.org` — public hostname for Home Assistant (TLS via cert-manager, real Let's Encrypt cert), routed by `epigone/`'s IngressRoute
- `grafana.k8s.ecafe.org` — Grafana
- `tasks.k8s.ecafe.org` — taskmgt frontend (also on Tailscale as `taskmgt`)
- `webdav.k8s.ecafe.org` — WebDAV server, internal/Tailscale access (used by desktop Zotero)
- `webdav.tail611131.ts.net` — WebDAV server via Tailscale Funnel (`webdav/funnel-ingress.yaml`), trusted cert, works on-LAN and off (used by Zotero for Android); root URL, no path suffix. Required two one-time settings in the Tailscale admin console (not managed in this repo): "HTTPS Certificates" enabled (DNS tab) and the `funnel` node attribute granted to `tag:k8s` in the ACL policy
- `zephyr.ecafe.org` — DDNS endpoint

### Traefik Customization
The k3s-bundled Traefik is customized via `traefik/helmchartconfig.yaml` (a `HelmChartConfig`
targeting the `traefik` HelmChart k3s manages in `kube-system`) to set
`--providers.kubernetescrd.allowCrossNamespace=true`, required for the `epigone/` IngressRoute
to reference the `homeassistant-service` Service in the `home-assistant` namespace. Applying this restarts the Traefik pod
(brief downtime for all ingress hostnames).

## GitOps Principles

1. **Never `kubectl apply` without also updating the manifest here.** The repo is the source of truth.
2. **Never commit secrets in plaintext.** All secrets use SOPS+age encryption — see Secrets Management below.
3. **Record Helm release names, namespaces, and values** alongside chart installs (values files live next to templates).
4. **This directory must be sufficient to rebuild the cluster from scratch.** See `RUNBOOK.md`.
5. **Inactive or experimental manifests** are kept locally but `.gitignore`d until cleaned up.
6. **Keep `RUNBOOK.md` up to date** as the cluster evolves — update it whenever a new secret, bootstrap step, or post-rebuild check is added.

## Secrets Management

**Current approach:** SOPS+age encryption. Secret files are named `*-secret.yaml`, encrypted
in-place before committing, and automatically decrypted by Flux's kustomize-controller at apply time.

**SOPS configuration:** `.sops.yaml` in the repo root targets `*-secret.yaml` files.
The age public key is embedded there. The **private key** lives only at
`/Volumes/SSD/sync/secure/k8s-flux-age.agekey` — never committed.

**Secrets managed in git (SOPS-encrypted):**
- `flux-system/discord-webhook-secret.yaml` — Discord webhook for Flux notifications
- `syncthing/discord-webhook-secret.yaml` — Discord webhook for SyncThing conflict monitor
- `nas-monitor/discord-webhook-secret.yaml` — Discord webhook for NAS RAID alerts
- `nas-monitor/nas-ssh-key-secret.yaml` — SSH key for NAS RAID monitoring (port 9222)
- `webdav/webdav-secret.yaml` — hacdias/webdav config.yaml, contains bcrypt-hashed basic-auth password for the `zotero` user
- `tailscale/operator-oauth-secret.yaml` — Tailscale OAuth client ID + secret
- `prometheus/grafana-admin-secret.yaml` — Grafana admin username + password

**Secrets NOT in git (provisioned imperatively or auto-managed):**
- `epigone/epigone.ecafe.org-production` — TLS cert (managed by cert-manager, auto-renewed)
- `flux-system/flux-system` — SSH deploy key for `github.com/ennui2342/k8s`; **write-capable** key
  named `flux-system-readwrite` (GitHub key ID: 145092103). The private key is stored only in the
  cluster secret and is not persisted anywhere. **On cluster rebuild:** generate a new SSH keypair,
  update the cluster secret, and add the public key as a write-capable deploy key on the GitHub repo
  (replacing the old key). The previous read-only key `flux-system-main-flux-system-./` (ID:
  145088789) was deleted — image automation requires write access to push tag updates.
- `flux-system/sops-age` — age private key for SOPS decryption; loaded from `/Volumes/SSD/sync/secure/k8s-flux-age.agekey` at bootstrap time

**Adding a new secret:** create a `*-secret.yaml` file next to the app manifests, add it to the
app's `kustomization.yaml` resources list, run `sops --encrypt --in-place <file>`, then commit.
See `RUNBOOK.md` for the full procedure.

## Flux Setup

Flux is bootstrapped pointing at `github.com/ennui2342/k8s`, branch `main`.
The Flux system manifests live in `flux-system/` (auto-generated by bootstrap, do not edit manually).

### taskmgt Image Automation

Flux watches GHCR for new image tags and updates `taskmgt/api.yaml` and `taskmgt/frontend.yaml`
automatically on push to this repo.

- **ImageRepository**: watches `ghcr.io/ennui2342/taskmgt-api` and `ghcr.io/ennui2342/taskmgt-frontend`
- **ImagePolicy**: semver filter `1.x.x` (format: `1.YYYYMMDD.RUNNUMBER`)
- **ImageUpdateAutomation**: commits updated image tags back to this repo; Flux then reconciles

Manifests: `flux-system/taskmgt-image-automation.yaml`

### Discord Notifications

Flux alerts on deployment events via Discord webhook.
Manifests: `flux-system/discord-alert.yaml`

## CVE Patch Management

Weekly Trivy scan (`monitoring/cve-scanner` CronJob, Monday 07:00, `trivy/trivy.yaml`) files one
`tm` task per vulnerable image (`+cli.claude-code.k8s <cli.cve-scanner`), deduping on creation and
auto-closing tasks for images no longer flagged. A Mac-side aswarm pipeline
(`/Volumes/SSD/pipelines/nightly-agents.yaml`, 1am/6am) works the queue: an orchestrator selects
the highest-priority task and routes it to an upgrade or health specialist subagent. The upgrade
specialist's prompt lives at `~/projects/agents/k8s/nightly-upgrade-prompt.md` (its own separate,
tracked git repo — not part of this one).

Images with no upstream fix get rebuilt locally and forked (`ghcr.io/ennui2342/*-patched`,
`imagePullPolicy: Never`, imported directly into node containerd — no registry push). Every fork
is tracked in `trivy/patched-images.yaml` alongside a reproducible Dockerfile under
`trivy/patched-images/<name>/`. The same scan also re-checks each fork's plain upstream image
weekly and files a `<cli.reconcile-scanner` task to revert once upstream ships an equivalent fix —
see `RUNBOOK.md`'s "CVE Patch Management" section for the full mechanics.

## Directory Structure Notes

```
cert-manager/     — Flux HelmRelease + HelmRepository (jetstack) + ClusterIssuer
coredns/          — CoreDNS custom config (*.k8s.ecafe.org wildcard)
flux-system/      — Flux bootstrap output + SOPS patch + alert config
dashboards/       — Custom Grafana dashboard ConfigMaps (Solar, Observatory, NAS Monitor, Weather Station)
epigone/          — epigone.ecafe.org namespace: cert-manager Certificate + IngressRoute fronting Home Assistant
health-monitor/   — CronJob: cluster health checks (CrashLoopBackOff, failed Flux kustomizations, NotReady nodes) → tm tasks
home-assistant/   — HA deployment, service, ingress, cleanup CronJob
mdns/             — mdns-repeater DaemonSets (master + worker), hostNetwork mDNS relay
monitoring/       — InfluxDB, Telegraf, Loki, Promtail; all monitoring stack manifests
prometheus/       — kube-prometheus-stack HelmRelease + HelmRepository + grafana-admin secret
mosquitto/        — Mosquitto deployment, configmap, service
nas-monitor/      — CronJob: SSH to NAS, parse /proc/mdstat, Discord alert
nfs/              — NFS provisioner Helm template
ring-mqtt/        — ring-mqtt deployment, PVC, service
solar/            — modpoll deployment and Modbus configmap
syncthing/        — SyncThing deployment, PVCs, service, ingress, conflict CronJob
tailscale/        — Flux HelmRelease + HelmRepository (tailscale) + Connector CR
taskmgt/          — taskmgt app manifests + Flux image automation
traefik/          — HelmChartConfig customizing k3s's bundled Traefik (allowCrossNamespace)
trivy/            — Weekly CVE scanner CronJob; patched-images.yaml tracks custom image forks + reconciliation
webdav/           — hacdias/webdav deployment, PV/PVC, service, internal ingress, Tailscale Funnel ingress, config secret (Zotero PDF sync)
website/          — nginx/PHP StatefulSet, configmaps, ingress
```

## Orienting a New Claude Instance

1. Run `kubectl get pods -A -o custom-columns='NODE:.spec.nodeName,NS:.metadata.namespace,POD:.metadata.name,STATUS:.status.phase' --no-headers | grep -v Completed | sort` to see live pod placement.
2. Check `kubectl get helmrelease -A` for Flux HelmRelease status.
3. Check `kubectl get gitrepository,kustomization,imagepolicy,imageupdateautomation -A` for Flux status.
4. The cluster is the source of truth for what's *running*; this repo is the source of truth for what *should* run.
5. Inactive/historical manifests exist locally but are gitignored — they may be stale.
6. SSH to master: `ssh ubuntu@k8s.local`. Workers only reachable from there.
7. Use `kubectl` locally — do not SSH to k8s.local just to run kubectl.
