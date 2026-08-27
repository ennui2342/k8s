# k8s Fleet Repository

This is the GitOps source of truth for the homelab Kubernetes cluster at `k8s.local`.
All active app manifests live here. Flux reconciles the cluster against this repo.

## Cluster Topology

- **k3s** v1.32.13+k3s1
- **OS**: Ubuntu Server 26.04 LTS on all four nodes (rebuilt 2026-08-22, replacing the original Ubuntu 20.04 install that had gone EOL with no ESM attached — see RUNBOOK.md's "Phase 0" and git history around that date for the rebuild). cgroup v2 throughout, which matters: it's what previously blocked a k3s v1.36 upgrade attempt (hard-refused to start on the old cgroup v1 install) — that upgrade is unblocked now but hasn't been re-attempted since.
- **Master** (`k8s`, `ubuntu@k8s.local`, `192.168.0.8`): control plane only — tainted `node-role.kubernetes.io/control-plane:NoSchedule`. Directly accessible from dev Mac via SSH and kubeconfig. Single node, no HA (deliberate — see RUNBOOK.md's "Master Datastore Backup & Restore"); daily SQLite/kine datastore + TLS/cred backup to the NAS instead, node-local cron, not GitOps-managed. The 2026-08-22 rebuild included the first real end-to-end rehearsal of restoring this backup onto genuinely replacement hardware (not just a local integrity check) — worked cleanly first attempt; see RUNBOOK.md for what that surfaced (a k3s node-password gotcha when workers are also fresh hardware under the same procedure).
- **Workers**: `k8s-1` (`192.168.0.81`), `k8s-2` (`192.168.0.82`), `k8s-3` (`192.168.0.83`, added 2026-08-22) — all directly reachable from the dev Mac via SSH, same as master (flat network, see below; the old "workers reachable from master only" hop requirement no longer applies).
- **Physical network** (see RUNBOOK.md's "Physical & Network Topology" for the full history): flat `192.168.0.0/24` — master and all three workers connect as peers to the same switch, which uplinks straight to the home router. Replaced an earlier design where master routed the workers' traffic over its own Wi-Fi link (kept for the tower's portability); that link was retired once the NAS connection itself needed a wired path for reliability, at which point the portability the Wi-Fi design bought was moot anyway. **Current deviation (as of 2026-08-23):** the tower is temporarily beside the desk rather than under the stairs near the NAS's own switch segment, so the switch's uplink back to the NAS currently runs over a powerline Ethernet adapter — suspected cause of the elevated/jittery NAS ping latency behind the recurring IOWait alerts (tm task `50cad5c2`). Planned fix: move the tower back under the stairs once the SD card upgrades are done, removing the powerline hop. See RUNBOOK.md for the full evidence.
- **Ingress**: Traefik v3 (bundled with k3s)
- **Storage**: NFS StorageClass `nfs-client` backed by `192.168.0.76:/mnt/md0/k8s` (all PVs are NFS — no local disk dependency)
- **VPN**: Tailscale Kubernetes operator (namespace: `tailscale`)
- **TLS**: cert-manager with Let's Encrypt (ClusterIssuer: `letsencrypt-prod`). Note: `*.k8s.ecafe.org` is internal DNS only — do not attempt TLS for those hostnames.
- **DNS for `*.k8s.ecafe.org` on Tailscale clients**: the Tailscale admin console has a Split DNS entry routing the `k8s.ecafe.org` domain (and all subdomains) straight to this cluster's CoreDNS (`10.43.0.10`, the `kube-dns` ClusterIP) rather than public DNS — Tailscale clients can reach that ClusterIP directly over the tailnet-routed service CIDR, avoiding the same home-router NAT-hairpin problem `webdav`'s Funnel ingress works around (see that entry above). CoreDNS answers with Traefik's own ClusterIP (`coredns/coredns-custom.yaml`, a `template` plugin override) rather than forwarding, so Tailscale clients hit Traefik directly without ever leaving the cluster network. Confirmed live 2026-08-23: the override's regex originally required a label before `k8s` (matching `grafana.k8s.ecafe.org` etc.) but not the bare apex `k8s.ecafe.org` itself, making the website completely unreachable for any Tailscale-connected client (while working fine on-LAN or off-Tailscale, and while the site/pod/ingress were all completely healthy the whole time) — fixed by widening the regex to make the leading label optional. Worth checking this override first for any future "site X.k8s.ecafe.org / k8s.ecafe.org isn't loading, but only for me" report before assuming an app-level problem.
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

## Cluster Hygiene Checklist

See `LINT.md` — the mechanically-checkable manifest standard for this repo, deliberately kept
out of this file so it can grow without adding context weight to every unrelated session.
**Check it before writing or editing any manifest**, the same way you'd run a linter before
committing. The periodic fleet audit and the nightly upgrade specialist both consult it
directly (and the audit extends it); this pointer is what makes sure an interactive session does
too.

## Actively Deployed Services

| Namespace | Service | Manifests | Notes |
|-----------|---------|-----------|-------|
| `botkube` | botkube | `botkube/` | Flux HelmRelease; Discord alerts + kubectl/helm/flux executors |
| `cert-manager` | cert-manager | `cert-manager/` | Flux HelmRelease (v1.x.x); ClusterIssuer for ecafe.org |
| `default` | mosquitto | `mosquitto/` | MQTT broker, anonymous access, port 31883 (NodePort) |
| `default` | mdns-repeater | `mdns/` | Worker-only DaemonSet (master's own repeater removed 2026-08-22 during the flat-network migration — see git history — its sole job was bridging mDNS between master's two old physically-separate interfaces (private worker subnet + main LAN Wi-Fi), which no longer exist now that every node shares one flat switch; mDNS multicast works natively within a single broadcast domain, so nothing replaces it) repeating mDNS packets between the pod network (`cni0`) and the host's physical interface (`eth0`) so mDNS-discoverable devices stay visible to pods regardless of network topology; `hostNetwork: true`, `privileged: true`; image `127.0.0.1:30500/mdns-repeater:latest-patched` (locally patched, served from the local registry, `imagePullPolicy: IfNotPresent`) |
| `default` | modpoll | `solar/` | Reads FoxESS inverter via Modbus at 192.168.0.188, publishes to `solar/foxess` on MQTT |
| `default` | nfs-provisioner | `nfs/template.yaml` | NFS subdir external provisioner |
| `default` | syncthing | `syncthing/` | SyncThing file sync; config + data on NFS |
| `default` | webdav | `webdav/` | hacdias/webdav server for Zotero PDF attachment sync; 20Gi NFS PV; `webdav.k8s.ecafe.org` ingress (internal/Tailscale, used by desktop Zotero) plus a Tailscale-operator Funnel Ingress (`webdav-funnel`) giving a trusted `*.ts.net` cert that works identically on-LAN and off — needed because Zotero for Android refuses self-signed/internal certs and the epigone.ecafe.org path hit home-router NAT-hairpin issues when accessed from inside the LAN; basic-auth user `zotero`, bcrypt password in `webdav-secret.yaml` |
| `default` | web | `website/` | nginx + PHP-FPM StatefulSet; serves k8s.ecafe.org |
| `epigone` | epigone routing | `epigone/` | Owns the `epigone.ecafe.org` cert-manager Certificate + Traefik IngressRoute for Home Assistant. Kept as its own namespace (decoupled from home-assistant) since it was briefly shared with webdav too; webdav now uses Tailscale Funnel instead (see below), so this currently only fronts Home Assistant, but stays separate in case another service needs the same public hostname later. |
| `freshrss` | freshrss | `freshrss/` | Self-hosted RSS reader, replacing Feedly — phase 1 of a Readwise Reader self-hosted evaluation (see `linkding`/`wallabag` below for the other phases). NFS-backed data + extensions PVCs; `rss.k8s.ecafe.org` ingress plus a Tailscale ingress for PWA/app installability testing. Custom `User-Agent` override (see recent commits) to fix bot-blocked feeds. Runs a locally-patched image (`127.0.0.1:30500/freshrss:1.29.1-patched`, see `trivy/patched-images.yaml`) — `1.29.1` is still the latest upstream release, so no plain tag bump picks up Debian 13 (trixie)'s apache2/php8.4/curl/expat CVE fixes. |
| `home-assistant` | homeassistant | `home-assistant/ha-*.yaml` | HA 2026.4.4, ClusterIP Service (not `hostNetwork` — corrected 2026-07-29, `ha-deployment.yaml` doesn't set it, only the `mdns-repeater` DaemonSet in this repo does), config on NFS; reachable at `home-assistant.k8s.ecafe.org` and, via `epigone/`, at `epigone.ecafe.org` |
| `home-assistant` | ring-mqtt | `ring-mqtt/` | Ring doorbell → MQTT bridge, RTSP port 30002 |
| `isfdb` | isfdb-mirror | `isfdb/` | Self-hosted mirror of the Internet Speculative Fiction Database (ISFDB) — MariaDB StatefulSet (NFS PVC) seeded from ISFDB's weekly "5.5-compatible" MySQL backup, fronted by a small adapter service (`isfdb-adapter`, custom image `127.0.0.1:30500/isfdb-mirror:<tag>`, served from the local registry) exposing ISBN/title/series/author lookups as JSON at `isfdb-adapter.k8s.ecafe.org` (internal DNS only). A weekly CronJob (`isfdb-refresh`, Sunday 08:00 UTC) logs into the Cloudflare-protected + login-gated ISFDB wiki (`cloudscraper` + a plain MediaWiki form POST), scrapes the current Google Drive backup link, downloads it (`gdown`), and atomically swaps it into the live DB only after a row-count sanity check — a failed refresh leaves last week's data live. As of 2026-08-19, the refresh job also posts run-start/complete/failure notifications to Discord (same bot REST API + embed shape as opsimath's `Notifications::DiscordNotifier`, same channel) — see the `isfdb-secret.yaml` entry below — giving visibility into *when* a run starts (before the ~20+ minute DB-load window), not just eventual success/failure. Originally built to back a self-hosted ISFDB metadata provider for `librarium/` (permanently removed from this cluster 2026-08-22 — see git history); still actively consumed by `opsimath/` (see that entry — reaches it via `isfdb-adapter.isfdb.svc.cluster.local:8080`), since ISFDB has no public API and Open Library/Google Books/Hardcover are too sparse for older or small-press SFF editions. **The adapter's source lives at `~/projects/isfdb-adapter/`** (public repo `ennui2342/isfdb-adapter`, its own reference implementation) — not in this repo. See `RUNBOOK.md`'s "ISFDB mirror" section for the clone/build/import rebuild steps. |
| `linkding` | linkding | `linkding/` | Self-hosted bookmark manager ("pinboard" — see the `pinboard` Claude Code skill), at `pinboard.k8s.ecafe.org` plus a Tailscale ingress for PWA installability. A CronJob (`linkding-task-sync`) polls linkding for bookmarks tagged `-task`, creates a corresponding `tm` task (`<cli.linkding-task-sync` provenance) for each, then strips the tag so the bookmark isn't re-processed — task lifecycle then belongs entirely to `tm`, no separate dedupe/auto-close bookkeeping in the sync job itself. |
| `monitoring` | cve-scanner | `trivy/` | Weekly Trivy scan → dedupes/files/auto-closes `tm` tasks; see CVE Patch Management below |
| `monitoring` | grafana | `prometheus/helmrelease.yaml` | grafana.k8s.ecafe.org, anonymous viewer access; managed by kube-prometheus-stack chart |
| `monitoring` | health-monitor | `health-monitor/` | CronJob, 30min: Flux Kustomization/HelmRelease failed-or-stalled checks (the only kubectl-based check left — CrashLoopBackOff/PVC/Node checks were removed 2026-07-27, now redundant with kube-prometheus-stack's default rules) **plus bridges every firing Alertmanager alert into a `<cli.cluster-health` `tm` task** (dedup/close on the alert's own fingerprint) — see Monitoring & Alerting below |
| `monitoring` | influxdb | `monitoring/influxdb.yaml` | InfluxDB 1.8.0, 8Gi NFS PV |
| `monitoring` | kube-prometheus-stack | `prometheus/` | Flux HelmRelease (70.x.x); Prometheus + Alertmanager + Grafana + node-exporter + kube-state-metrics. Alertmanager → Discord routing exists (`prometheus/helmrelease.yaml`) but was silently broken from when it was first configured until 2026-07-27 (this Alertmanager version doesn't support `discord_configs`' `webhook_url_file`, so every operator reconcile failed — fixed via `HelmRelease.spec.valuesFrom` injecting the secret value directly instead) |
| `monitoring` | nas-monitor | `nas-monitor/` | CronJob, 15min: SSH to the NAS, parse `/proc/mdstat`, Discord alert on RAID degradation; SSH key also reused by `pvc-usage-monitor` |
| `monitoring` | os-eol-scanner | `os-eol-scanner/` | CronJob, weekly (Mon 07:30): reads each node's `status.nodeInfo.osImage` via the k8s API (no SSH needed) and flags Ubuntu LTS EOL approaching/passed — closes the gap the CVE scanner can't (trivy only scans container images, never the host OS) that let the whole fleet sit on an EOL, unpatched Ubuntu 20.04 for over a year unnoticed (tm task `b914610a`, resolved 2026-08-22 with a full node rebuild). No ESM assumed, since this fleet has never had it attached. Deliberately files tasks **untagged** (no `#~upgrade`/`#~deploy`/`#~health`) — an OS reimage is hardware-touching work like `b914610a` was, not something to auto-route to a specialist; `++ennui2342` for backlog visibility instead |
| `monitoring` | pvc-usage-monitor | `pvc-usage-monitor/` | CronJob, 2h: real per-PVC usage vs. each PVC's own requested size, via `du` over SSH to the NAS (reuses `nas-monitor`'s key) — `kubelet_volume_stats_*` can't do this on this StorageClass, see that directory's script comment. Fires a `<cli.cluster-health` task at 90% of request; `nfs-subdir-external-provisioner` enforces no real quota, so this is a self-imposed budget check, not a hard limit |
| `registry` | registry | `registry/` | `registry:2`, NFS-backed PVC, NodePort 30500, plain HTTP + anonymous (LAN-only, never exposed beyond it). Target for locally-built images, replacing `docker save`/`scp`/`ctr images import` — see `RUNBOOK.md`'s "Local container registry" for the one-time per-node containerd trust config and Mac-side Docker Desktop config this needs (neither is GitOps-managed, both are node/workstation-local). Confirmed live 2026-07-29 (updated 2026-08-01 — `linkding` and `wallabag` forks added since): migration is complete — every custom/forked image in the repo (`mdns-repeater`, `isfdb-mirror`, `mosquitto`, `modpoll`, `home-assistant`, `telegraf`, `ring-mqtt`, `trivy`, `botkube`, `linkding`, `wallabag`, the Flux controllers, `k8s-toolbox`) is now pulled from `127.0.0.1:30500` with `imagePullPolicy: IfNotPresent`; no manifest in the repo still uses `imagePullPolicy: Never` |
| `monitoring` | loki | `monitoring/loki.yaml` | Flux HelmRelease (6.x.x); log aggregation, 31-day retention, NFS storage |
| `monitoring` | promtail | `monitoring/promtail.yaml` | Flux HelmRelease (chart pinned `6.17.x`); ships pod logs to Loki. Runs a locally-patched image (`127.0.0.1:30500/promtail:3.6.11-patched`, see `trivy/patched-images.yaml`) via `values.image` override — promtail is fully EOL upstream (deprecated in favor of Grafana Alloy, commercial support ended 2026-02-28), `grafana/promtail:3.6.11` is the last image Grafana will ever publish for it, and the `promtail` Helm chart hasn't had a release since 6.17.1 (still `appVersion: 3.5.1`), so there's no plain upstream tag or chart bump that can ever resolve OS-package CVEs here again |
| `monitoring` | telegraf | `monitoring/telegraf.yaml` | Scrapes MQTT (mosquitto.default:1883), statsd, SNMP (NAS at 192.168.0.76) |
| `opsimath` | opsimath | `opsimath/` | Rails 8.1 / Ruby 4.0 app (tm ticket `748e2eac`) — web (Puma via Thruster) + a Solid Queue worker (no Redis/Sidekiq) + a dedicated Postgres 18 instance, all in-namespace. Syncs a Goodreads "to-read"-style feed and posts Discord notifications; reaches `isfdb-adapter` over in-cluster Service DNS (`isfdb-adapter.isfdb.svc.cluster.local:8080`) — deliberately not the public Traefik hostname, which resolves inconsistently depending on whether Tailscale's DNS resolver is in a given client's path. `opsimath.k8s.ecafe.org` ingress plus a Tailscale ingress for the user's own remote access. Active Storage (cover images) PVC is `ReadWriteMany`, not this repo's usual `ReadWriteOnce` — web and worker are separate Deployments both needing concurrent write access, since Goodreads sync (which attaches covers) runs on the worker. Also runs `opsimath-cover-compare` (tm task `b54a5adc`), a stateless Python/FastAPI ORB+RANSAC image-similarity sidecar Deployment (no DB, no secrets, no persistent storage, ClusterIP-only, no Ingress) called by the worker over in-cluster Service DNS during Goodreads enrichment. **App source lives at `~/projects/opsimath/`, not in this repo** (public repo `ennui2342/opsimath`) — this repo only has the deployment manifests. Unlike isfdb-adapter/librarium's manual local-registry builds, opsimath is fully automated (`taskmgt/`-style): its own CI pushes versioned tags to `ghcr.io/ennui2342/opsimath` and `ghcr.io/ennui2342/opsimath-cover-compare`, and Flux image automation (`flux-system/opsimath-image-automation.yaml`, a single `ImageUpdateAutomation` covering both images) redeploys automatically — see `RUNBOOK.md`'s "opsimath" section for the from-scratch-rebuild fallback only. |
| `tailscale` | operator | `tailscale/` | Flux HelmRelease (1.x.x); `ts-k8s-connector` exposes taskmgt frontend; also runs the Funnel proxy for webdav (`ts-webdav-funnel` StatefulSet, auto-created from `webdav/funnel-ingress.yaml`) |
| `taskmgt` | api + frontend | `taskmgt/` | Task management app; see Flux image automation below |
| `wallabag` | wallabag | `wallabag/` | Self-hosted read-it-later app, replacing Instapaper — phase 1 of the Readwise Reader self-hosted evaluation alongside `freshrss`. NFS-backed data + images PVCs; `later.k8s.ecafe.org` ingress plus a Tailscale ingress for PWA installability testing. Runs a locally-patched image (`127.0.0.1:30500/wallabag:2.6.14-patched`, see `trivy/patched-images.yaml`) — no newer upstream `2.6.14`-line tag exists to pick up Alpine 3.19.8's musl/php81 CVE fixes. **Known gap:** still running the default `wallabag`/`wallabag` admin account as of 2026-07-29 — needs replacing post-deploy (see commit 7e62573). |

### Key Ingress Hostnames
- `k8s.ecafe.org` — website
- `syncthing.k8s.ecafe.org` — SyncThing web UI, internal DNS only
- `home-assistant.k8s.ecafe.org` — Home Assistant (internal DNS only)
- `isfdb-adapter.k8s.ecafe.org` — ISFDB mirror adapter JSON API, internal DNS only
- `epigone.ecafe.org` — public hostname for Home Assistant (TLS via cert-manager, real Let's Encrypt cert), routed by `epigone/`'s IngressRoute
- `grafana.k8s.ecafe.org` — Grafana
- `rss.k8s.ecafe.org` — FreshRSS (also on Tailscale, for PWA installability off-LAN)
- `pinboard.k8s.ecafe.org` — linkding bookmark manager (also on Tailscale as `pinboard.tail611131.ts.net`)
- `later.k8s.ecafe.org` — wallabag read-it-later (also on Tailscale, for PWA installability off-LAN)
- `opsimath.k8s.ecafe.org` — opsimath (also on Tailscale as `opsimath.tail611131.ts.net`), for the user's own remote access
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
- `nas-monitor/discord-webhook-secret.yaml` — creates `discord-webhook` in the `monitoring` namespace; despite living in `nas-monitor/`, this is the shared secret `health-monitor`, `trivy`, and `pvc-usage-monitor` also read (each just references it by name, no separate copy) — don't assume it's NAS-specific or safe to remove if `nas-monitor` is ever decommissioned
- `nas-monitor/nas-ssh-key-secret.yaml` — SSH key for the NAS (port 9222), used by both `nas-monitor` (RAID monitoring) and `pvc-usage-monitor` (per-PVC `du`) — same multi-consumer caveat as above
- `webdav/webdav-secret.yaml` — hacdias/webdav config.yaml, contains bcrypt-hashed basic-auth password for the `zotero` user
- `tailscale/operator-oauth-secret.yaml` — Tailscale OAuth client ID + secret
- `prometheus/grafana-admin-secret.yaml` — Grafana admin username + password
- `isfdb/isfdb-secret.yaml` — MariaDB root password, `ISFDB_WIKI_USERNAME`/`ISFDB_WIKI_PASSWORD` for the weekly refresh job's ISFDB wiki login, plus `DISCORD_BOT_TOKEN`/`DISCORD_CHANNEL_ID` (added 2026-08-19) for `refresh.py`'s run-start/complete/failure notifications — reuses the exact same bot token + channel ID as `opsimath/opsimath-secret.yaml`'s `Notifications::DiscordNotifier` (Rails encrypted credentials `discord.bot_token`/`discord.channel_id`, not itself mirrored into `opsimath-secrets`), so isfdb-refresh notifications land in the same Discord channel as opsimath's own for easy side-by-side correlation — Mark's own suggested default; redirect to a separate channel later if he'd rather
- `botkube/botkube-secret.yaml` — botkube's Helm `values.yaml` (contains the Discord webhook botkube alerts to)
- `freshrss/freshrss-secret.yaml` — `FRESHRSS_INSTALL`/`FRESHRSS_USER` bootstrap admin credentials
- `linkding/linkding-secret.yaml` — `LD_SUPERUSER_NAME`/`LD_SUPERUSER_PASSWORD`/`LD_SUPERUSER_EMAIL` bootstrap admin credentials
- `linkding/linkding-api-secret.yaml` — creates `linkding-api-token`, linkding's own API token, consumed by the `linkding-task-sync` CronJob
- `wallabag/wallabag-secret.yaml` — `SYMFONY__ENV__SECRET` app secret (wallabag admin credentials are still the shipped default as of 2026-07-29 — see `tm` task 8fc03e95)
- `opsimath/opsimath-secret.yaml` — `RAILS_MASTER_KEY` (decrypts `config/credentials.yml.enc`, which holds `secret_key_base` plus real Goodreads and Discord bot secrets — never baked into the image or committed anywhere, per the source repo's own `config/master.key`, itself gitignored there too) and `APP_DATABASE_PASSWORD` for the bundled Postgres

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

## Monitoring & Alerting

**Principle: an alert that needs action must produce a tracked task, not just a Discord message.**
A Discord ping alone is easy to miss or forget — it competes with every other channel message,
has no owner, no priority, and nothing re-surfaces it. Confirmed live 2026-07-27: Alertmanager's
Discord delivery had been silently broken since it was first configured (this Alertmanager
version doesn't support `discord_configs`' `webhook_url_file` — every operator reconcile failed),
and separately, once fixed, a correctly-firing `KubeJobFailed` alert had already been sitting
unactioned for 24+ hours because nothing turned "alert fires" into "someone/something is on the
hook to look at it." Every alerting mechanism in this cluster should end in a `tm` task (usually
via the `<cli.cluster-health` or `<cli.cve-scanner`/`<cli.reconcile-scanner` source tags, which
route through the agent-orchestrator pipeline — see CVE Patch Management below), with Discord as a
secondary, immediate-visibility notification alongside it, not a replacement for it. This applies
symmetrically to closing: a task that auto-closes should also post to Discord, not just go quiet.
**Corollary: keep Alertmanager's `repeat_interval` long (default: 24h), not short.** Once a
`tm` task exists for an alert, that task — not Discord — is the durable, ongoing tracker; a
short `repeat_interval` (the Alertmanager default is much shorter) just re-spams Discord with
the same already-tracked, unchanged failure while nothing new is happening. Confirmed live
2026-08-27: a weekly `isfdb-refresh` CronJob failure sat for 4 days re-notifying every 4h (~24
pings) for one already-filed task, before the next scheduled run could even retry it. Don't
drop `repeat_interval` to zero/disable it entirely, though — some periodic re-notification is
still worth keeping as an independent safety net in case the task-bridge itself silently breaks
(see the `health-monitor` blind-spot corollary below, `tm` task `54e03d81`) — 24h is long enough
to kill the spam while still catching that failure mode within a day. This is the default for
*all* alerts routed through Alertmanager (`prometheus/helmrelease.yaml`'s `route.repeat_interval`),
not something to tune per-alert or per-CronJob.
**Corollary, confirmed live 2026-08-24/25: a bridge that can't reach its own data source must fail
loud, never silently report "all clear."** `health-monitor` went blind to Alertmanager for at least
the tail end of a 2-day `k8s-1` `NodeNotReady` outage (root cause: a hostname collision with `k8s-2`
baked into `k8s-1`'s cloud-init seed during the 2026-08-22 reimage — see `tm` task `54e03d81`), and
reported "no issues" every 30 minutes instead — even though `KubeNodeNotReady`/
`KubeStatefulSetReplicasMismatch` were firing continuously the whole time and would otherwise have
caught it on the first run. It now files its own `!1` task when the Alertmanager fetch fails, and —
found only by live-testing that fix, not by reading the code — a matching bug where "no data" was
misread as "nothing firing," silently auto-closing genuinely still-firing alert tasks during the
same outage window. Both are fixed (`health-monitor/health-monitor.yaml`). Any future
Alertmanager-bridging or similar polling script should apply the same rule: an unreachable data
source is itself an alertable condition, and must never be allowed to look identical to "checked,
found nothing."

`kube-prometheus-stack`'s default `PrometheusRule`s (Alertmanager, routed to Discord via
`prometheus/helmrelease.yaml`) already cover most general cluster-health failure modes
(CrashLoopBackOff, NotReady nodes, PVC errors, stuck Jobs, container-waiting-reason problems like
`ImagePullBackOff`/`ErrImageNeverPull` — this last one is what let a stuck `cve-scanner` pod run
for over an hour undetected before this repo had anything watching for it) — prefer relying on
and, if needed, tuning these over writing new bespoke Python detection scripts. `health-monitor/`
bridges every firing Alertmanager alert into a `tm` task this way; only write a new custom
`PrometheusRule` (`prometheus/alerting-rules.yaml`) or a genuinely custom script when the data
Prometheus already collects can't answer the question — e.g. `pvc-usage-monitor/` exists because
`kubelet_volume_stats_*` cannot give real per-PVC usage on this NFS StorageClass (confirmed live:
every PVC reports identical values, since kubelet does a cheap `statfs()` on the shared mount, not
a real per-directory walk — this is also why `prometheus/alerting-rules.yaml`'s
`PersistentVolumeFillingUp` is a single cluster-wide alert rather than per-PVC).

**Principle: lightweight/periodic CronJobs should use `k8s-toolbox/` (or another pre-built,
`imagePullPolicy: IfNotPresent` image pulled from the local registry), never `apk add`/`apk
update && apk upgrade` at runtime.**
Confirmed live 2026-07-27: a "flapping NodeHighIOWait" alert on k8s-2 (a Pi-class node whose entire
root filesystem is one already-79%-full eMMC/SD card) turned out to have nothing to do with the NFS
server — its physical disk stayed under 6% utilization throughout, including during a confirmed
35% CPU-iowait spike on k8s-2 at the same instant. The real cause was several CronJobs
(`nas-raid-monitor`, `cluster-health-monitor`, `linkding-task-sync`, ...) each reinstalling Alpine
packages from scratch on every single invocation — real local disk writes, every 15-30 minutes, on
whatever node the scheduler picked, compounding whenever multiple jobs landed on the same node
together (as they did at the exact spike moment). `health-monitor`'s original "live-upgrade"
pattern (apk update/upgrade every run, to dodge a static image going stale on CVEs) predates the
reconcile-scanner mechanism above and made sense before it existed — it no longer does, since a
static image now gets caught and flagged like any other image if it accumulates CVEs. Use
`127.0.0.1:30500/k8s-toolbox:1.32.13-20260802` (source: `k8s-toolbox/Dockerfile` — `alpine/k8s`
base, `apk update && apk upgrade` for current OS packages, plus `openssh-client curl jq python3
py3-yaml`) for any new lightweight CronJob needing these tools; extend that Dockerfile rather than
reaching for `apk add` in a `command:` block. Rebuild + repush with a new date-suffixed tag (same
`kubectl-version-YYYYMMDD` pattern) whenever the weekly CVE scan flags this image or the k3s
version bumps.

## CVE Patch Management

Weekly Trivy scan (`monitoring/cve-scanner` CronJob, Monday 07:00, `trivy/trivy.yaml`) files one
`tm` task per vulnerable image (`+cli.claude-code.k8s <cli.cve-scanner`), deduping on creation and
auto-closing tasks for images no longer flagged. A Mac-side aswarm pipeline
(`/Volumes/SSD/pipelines/agent-orchestrator.yaml`, renamed 2026-08-19 from `nightly-agents`, then
`k8s-orchestrator` — general-purpose task routing, not k8s-specific, though its only live wiring
today is this repo — runs every 30min, though CVE/health work still only dispatches during the
1am/6am window) works the
queue: an orchestrator selects the highest-priority eligible task and routes it by tag to an
upgrade, health, or deploy specialist subagent. The upgrade specialist's prompt lives at
`~/projects/agents/k8s/upgrade-prompt.md` (its own separate, tracked git repo — not part
of this one).

Trivy's scan is container-image-only — it never sees the host OS itself, which is why the
whole fleet sat on an EOL, unpatched Ubuntu 20.04 for over a year with nothing catching it
(tm task `b914610a`, resolved 2026-08-22 via a full node rebuild). `monitoring/os-eol-scanner`
closes that specific gap (weekly, checks each node's Ubuntu version against known LTS EOL
dates) using the same file-a-task/dedupe/auto-close shape as the CVE scanner, but files tasks
**untagged** rather than routing them to the upgrade specialist — an OS reimage is real
hardware-touching work, not something to hand to an unattended agent the way an image rebuild
is.

Routine host-OS security patches themselves are handled by `unattended-upgrades`, present by
default on the base image, not something this repo configures — except the actual **reboot**
to activate a patch that needs one (kernel updates, mainly), which is: see
`node-provisioning/52unattended-upgrades-local.conf`, deployed by hand to every node (not
GitOps-managed, host-local like the containerd registry trust config and master's backup cron).
**Reserves 04:15–05:15 daily, staggered per node (master 04:15, `k8s-1` 04:30, `k8s-2` 04:45,
`k8s-3` 05:00, ~5min each in practice), for an automatic reboot** if one's pending — avoid
scheduling any new node-local cron entry or CronJob in that window. Staggered deliberately, not
a single shared time: every node runs the identical OS image, so an update needing a reboot
tends to land on all four within the same day or two, and a shared time would mean the whole
cluster going down simultaneously with no cross-node awareness — a smaller-scale echo of the
exact problem this fleet's 2026-08-19/22 rebuild was about. Master first so it's stable before
any worker needs to rejoin it. Chosen to sit clear of the two windows below and master's own
03:30 backup cron.

Images with no upstream fix get rebuilt locally and forked (`ghcr.io/ennui2342/*-patched`,
`imagePullPolicy: Never`, imported directly into node containerd — no registry push). Every fork
is tracked in `trivy/patched-images.yaml` alongside a reproducible Dockerfile under
`trivy/patched-images/<name>/`. The same scan also re-checks each fork's plain upstream image
weekly and files a `<cli.reconcile-scanner` task to revert once upstream ships an equivalent fix —
see `RUNBOOK.md`'s "CVE Patch Management" section for the full mechanics.

## Directory Structure Notes

```
botkube/          — Flux HelmRelease + Discord webhook secret; Discord alerts + kubectl/helm/flux executors
cert-manager/     — Flux HelmRelease + HelmRepository (jetstack) + ClusterIssuer
coredns/          — CoreDNS override resolving k8s.ecafe.org (apex + subdomains) straight to Traefik's ClusterIP, for Tailscale Split DNS clients — see Cluster Topology's DNS note above
flux-system/      — Flux bootstrap output + SOPS patch + alert config
dashboards/       — Custom Grafana dashboard ConfigMaps (Solar, Observatory, NAS Monitor, Weather Station)
epigone/          — epigone.ecafe.org namespace: cert-manager Certificate + IngressRoute fronting Home Assistant
freshrss/         — Self-hosted RSS reader (Readwise Reader evaluation, phase 1): deployment, data/extensions PVCs, internal + Tailscale ingress, bootstrap secret
health-monitor/   — CronJob: Flux Kustomization/HelmRelease checks + Alertmanager→tm bridge (see Monitoring & Alerting)
home-assistant/   — HA deployment, service, ingress, cleanup CronJob
isfdb/            — Self-hosted ISFDB mirror: MariaDB StatefulSet, adapter Deployment (JSON API over the mirror), weekly refresh CronJob; adapter/ holds the custom image source (Dockerfile, adapter.py, refresh.py)
k8s-toolbox/      — Dockerfile only, no manifests: shared image for lightweight CronJobs (kubectl + openssh-client/curl/jq/python3/py3-yaml), see Monitoring & Alerting
linkding/         — Self-hosted bookmark manager: deployment, data PVC, internal + Tailscale ingress, bootstrap + API-token secrets, linkding-task-sync CronJob (bookmark→tm bridge)
mdns/             — mdns-repeater DaemonSet (worker-only), hostNetwork mDNS relay between pod network and host interface
monitoring/       — InfluxDB, Telegraf, Loki, Promtail; all monitoring stack manifests
prometheus/       — kube-prometheus-stack HelmRelease + HelmRepository + grafana-admin secret + custom PrometheusRule (alerting-rules.yaml)
mosquitto/        — Mosquitto deployment, configmap, service
nas-monitor/      — CronJob: SSH to NAS, parse /proc/mdstat, Discord alert
nfs/              — NFS provisioner Helm template
opsimath/         — Rails app: web + Solid Queue worker Deployments, bundled Postgres 18 StatefulSet, RWX Active Storage PVC, internal + Tailscale ingress
os-eol-scanner/   — CronJob: weekly Ubuntu LTS EOL check across all nodes, files/auto-closes tm tasks (untagged, human-only — see CVE Patch Management below)
pvc-usage-monitor/ — CronJob: real per-PVC usage vs. requested size via NAS-side `du` over SSH (see Monitoring & Alerting)
registry/         — local container registry (registry:2), target for future custom image builds — see RUNBOOK.md
ring-mqtt/        — ring-mqtt deployment, PVC, service
solar/            — modpoll deployment and Modbus configmap
syncthing/        — SyncThing deployment, PVCs, service, ingress, conflict CronJob
tailscale/        — Flux HelmRelease + HelmRepository (tailscale) + Connector CR
taskmgt/          — taskmgt app manifests + Flux image automation
traefik/          — HelmChartConfig customizing k3s's bundled Traefik (allowCrossNamespace)
trivy/            — Weekly CVE scanner CronJob; patched-images.yaml tracks custom image forks + reconciliation
wallabag/         — Self-hosted read-it-later app (Readwise Reader evaluation, phase 1): deployment, data/images PVCs, internal + Tailscale ingress, secret
webdav/           — hacdias/webdav deployment, PV/PVC, service, internal ingress, Tailscale Funnel ingress, config secret (Zotero PDF sync)
website/          — nginx/PHP StatefulSet, configmaps, ingress
```

## Orienting a New Claude Instance

1. Run `kubectl get pods -A -o custom-columns='NODE:.spec.nodeName,NS:.metadata.namespace,POD:.metadata.name,STATUS:.status.phase' --no-headers | grep -v Completed | sort` to see live pod placement.
2. Check `kubectl get helmrelease -A` for Flux HelmRelease status.
3. Check `kubectl get gitrepository,kustomization,imagepolicy,imageupdateautomation -A` for Flux status.
4. The cluster is the source of truth for what's *running*; this repo is the source of truth for what *should* run.
5. Inactive/historical manifests exist locally but are gitignored — they may be stale.
6. SSH: `ssh ubuntu@k8s.local` (master) or directly to any worker (`192.168.0.81`/`.82`/`.83`) — flat network, no hop required.
7. Use `kubectl` locally — do not SSH to k8s.local just to run kubectl.
