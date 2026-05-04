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
| `default` | modpoll | `solar/` | Reads FoxESS inverter via Modbus at 192.168.0.188, publishes to `solar/foxess` on MQTT |
| `default` | nfs-provisioner | `nfs/template.yaml` | NFS subdir external provisioner |
| `default` | syncthing | `syncthing/` | SyncThing file sync; config + data on NFS |
| `default` | web | `website/` | nginx + PHP-FPM StatefulSet; serves k8s.ecafe.org |
| `home-assistant` | homeassistant | `home-assistant/ha-*.yaml` | HA 2026.4.4, hostNetwork, config on NFS |
| `home-assistant` | ring-mqtt | `ring-mqtt/` | Ring doorbell → MQTT bridge, RTSP port 30002 |
| `monitoring` | grafana | `prometheus/helmrelease.yaml` | grafana.k8s.ecafe.org, anonymous viewer access; managed by kube-prometheus-stack chart |
| `monitoring` | influxdb | `monitoring/influxdb.yaml` | InfluxDB 1.8.0, 8Gi NFS PV |
| `monitoring` | kube-prometheus-stack | `prometheus/` | Flux HelmRelease (70.x.x); Prometheus + Alertmanager + Grafana + node-exporter + kube-state-metrics |
| `monitoring` | loki | `monitoring/loki.yaml` | Flux HelmRelease (6.x.x); log aggregation, 31-day retention, NFS storage |
| `monitoring` | promtail | `monitoring/promtail.yaml` | Flux HelmRelease (6.x.x); ships pod logs to Loki |
| `monitoring` | telegraf | `monitoring/telegraf.yaml` | Scrapes MQTT (mosquitto.default:1883), statsd, SNMP (NAS at 192.168.0.76) |
| `tailscale` | operator | `tailscale/` | Flux HelmRelease (1.x.x); `ts-k8s-connector` exposes taskmgt frontend |
| `taskmgt` | api + frontend | `taskmgt/` | Task management app; see Flux image automation below |

### Key Ingress Hostnames
- `k8s.ecafe.org` — website
- `home-assistant.k8s.ecafe.org`, `epigone.ecafe.org` — Home Assistant (TLS via cert-manager)
- `grafana.k8s.ecafe.org` — Grafana
- `tasks.k8s.ecafe.org` — taskmgt frontend (also on Tailscale as `taskmgt`)
- `zephyr.ecafe.org` — DDNS endpoint

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
- `tailscale/operator-oauth-secret.yaml` — Tailscale OAuth client ID + secret
- `prometheus/grafana-admin-secret.yaml` — Grafana admin username + password

**Secrets NOT in git (provisioned imperatively or auto-managed):**
- `home-assistant/epigone.ecafe.org-production` — TLS cert (managed by cert-manager, auto-renewed)
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

## Directory Structure Notes

```
cert-manager/     — Flux HelmRelease + HelmRepository (jetstack) + ClusterIssuer
coredns/          — CoreDNS custom config (*.k8s.ecafe.org wildcard)
flux-system/      — Flux bootstrap output + SOPS patch + alert config
dashboards/       — Custom Grafana dashboard ConfigMaps (Solar, Observatory, NAS Monitor, Weather Station)
home-assistant/   — HA deployment, service, ingress, cert, cleanup CronJob
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
