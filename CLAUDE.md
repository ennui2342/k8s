# k8s Fleet Repository

This is the GitOps source of truth for the homelab Kubernetes cluster at `k8s.local`.
All active app manifests live here. Flux reconciles the cluster against this repo.

## Cluster Topology

- **k3s** v1.36.5+k3s1 (upgraded from the EOL v1.32.13 on 2026-10-24, one minor at a time). The version is declared in `k3s-upgrade/plans.yaml` and applied by system-upgrade-controller (`system-upgrade/`); to upgrade, bump both Plans and commit. See RUNBOOK's "Upgrading k3s" for the rules (one minor at a time, backup first, check the bundled Traefik chart, local-registry pull retries).
- **OS**: Ubuntu Server 26.04 LTS on all four nodes (rebuilt 2026-08-22, replacing the original Ubuntu 20.04 install that had gone EOL with no ESM attached — see RUNBOOK.md's "Phase 0" and git history around that date for the rebuild). cgroup v2 throughout, which matters: it's what previously blocked a k3s v1.36 upgrade attempt (hard-refused to start on the old cgroup v1 install) — the rebuild unblocked that upgrade, and it completed 2026-10-24 (see the k3s line above).
- **Master** (`k8s`, `ubuntu@k8s.local`, `192.168.0.8`): control plane only — tainted `node-role.kubernetes.io/control-plane:NoSchedule`. Directly accessible from dev Mac via SSH and kubeconfig. Single node, no HA (deliberate — see RUNBOOK.md's "Master Datastore Backup & Restore"); daily SQLite/kine datastore + TLS/cred backup to the NAS instead, node-local cron, not GitOps-managed. The 2026-08-22 rebuild included the first real end-to-end rehearsal of restoring this backup onto genuinely replacement hardware (not just a local integrity check) — worked cleanly first attempt; see RUNBOOK.md for what that surfaced (a k3s node-password gotcha when workers are also fresh hardware under the same procedure).
- **Workers**: `k8s-1` (`192.168.0.81`), `k8s-2` (`192.168.0.82`), `k8s-3` (`192.168.0.83`, added 2026-08-22) — all directly reachable from the dev Mac via SSH, same as master (flat network, see below; the old "workers reachable from master only" hop requirement no longer applies).
- **Physical network** (see RUNBOOK.md's "Physical & Network Topology" for the full history): flat `192.168.0.0/24` — master and all three workers connect as peers to the same switch, which uplinks straight to the home router. Replaced an earlier design where master routed the workers' traffic over its own Wi-Fi link (kept for the tower's portability); that link was retired once the NAS connection itself needed a wired path for reliability, at which point the portability the Wi-Fi design bought was moot anyway. From 2026-08-23 to 2026-09-06 the tower sat beside the desk with the switch's uplink to the NAS running over a powerline Ethernet adapter — the root cause of the recurring/jittery NAS ping latency behind the `NodeHighIOWait`/`NodeCriticalIOWait` alerts (tm task `50cad5c2`). **Resolved 2026-09-06:** tower moved back under the stairs onto the NAS's direct switch segment during the SD-card-work shutdown, powerline hop removed; post-move ping to the NAS is avg ~0.4ms / jitter <0.35ms from every node (was avg 25ms / jitter 19ms on `k8s-1`), and the Alertmanager IOWait silences were expired. See RUNBOOK.md for the full before/after.
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

### Nightly schedule: one maintenance window, two protected windows
**All times Europe/London.** These apply to anything that runs on or touches the cluster: CronJobs,
node-local cron/timers, recurring jobs inside apps (opsimath's and mg-reporting's Solid Queue
`config/recurring.yml`), the Mac's aswarm pipelines, and agent work.

- **Maintenance window: 05:10–05:55 daily.** Reserved for disruptive maintenance, today the
  health-gated node reboots (`node-provisioning/`): master 05:10, `k8s-1` 05:20, `k8s-2` 05:30,
  `k8s-3` 05:40. **Nothing else may be scheduled to start in it**, and a job that starts before
  it must be expected to finish by 05:10. Only jobs that run hourly or more often and are harmless
  to miss once are exempt (the NAS monitors, health-monitor, allsky-meteors, hourly cache warms).
- **Protected windows: 02:00–05:00 and 16:00–19:00.** Predbat (and HA, which it drives the
  inverter through) runs the home battery live, with no fallback schedule on the inverter: the
  Octopus Flux cheap charge is 02:00–05:00, the peak 16:00–19:00, and Predbat switches modes at
  02:00, 05:00, 16:00 and 19:00. **No planned disruption to `home-assistant` (HA, Predbat,
  ring-mqtt), `default/mosquitto` or `default/modpoll`, or to the nodes they run on**, in those
  windows: no reboots, drains, k3s upgrades, rollouts or restarts. Unattended agents defer such
  work to outside the windows; a human may override for a genuine emergency.
- **Use `timeZone: Europe/London`** on any CronJob tied to these windows. A UTC schedule drifts an
  hour against them every summer (BST). `LINT.md` checks CronJobs against all of this.
- **Keep this table current** when you add or move anything that runs overnight:

| Europe/London | What |
|---|---|
| every 30 min | agent-orchestrator (Mac); deploy every tick, upgrade/health specialists dispatch only at **01:00** and **06:00** (each up to 3h, so they must respect the protected windows themselves) |
| **02:00–05:00** | **protected: Flux cheap charge** |
| 02:30–04:50 | opsimath nightly batch, Europe/London since 2026-11-26 (tm `15f1e314`): line wants 02:30, known editions 02:40, wishlist 02:50, anchored refresh 03:30, decision sweep 03:45, mobile snapshot 03:55, eBay sweep 04:00 (~15 min), digest 04:30, cover warm-up 04:40 (~9 min). A test in opsimath keeps every nightly job starting before 05:00 UK time |
| 03:30 | master datastore backup (node-local cron) |
| **05:10–05:55** | **maintenance window: node reboots, if one is pending** |
| ~06:00–07:00 | `apt-daily-upgrade` on every node (jittered; a kernel it installs reboots at the next night's slot) |
| 06:15 | home-energy-monitor |
| 06:20 onwards | mg-reporting collectors (06:20–21:55) |
| 06:30 | isfdb-weekly-monitor (Mac, daily despite the name) |
| Mon 07:00 / 07:30 UTC | cve-scanner / os-eol-scanner |
| Sun 08:00 UTC | isfdb-refresh |
| **16:00–19:00** | **protected: peak** |

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
| `allsky` | indi-allsky (all-sky camera receiver) | `allsky/` | Web/SyncAPI side of indi-allsky: the garden camera Pi (`indi-allsky.local`) uploads every image, panorama, timelapse, keogram and star trail here over SyncAPI. Deliberately **not** `indi-allsky/` — that path is a stale, gitignored March-2024 upstream source clone. `allsky-web` Deployment (1 replica, `Recreate`): gunicorn (`ghcr.io/ennui2342/indi-allsky-web:<tag>`, upstream's `docker/Dockerfile.gunicorn` at the same indi-allsky commit as the Pi plus `expire.sh`; source `ennui2342/indi-allsky-web`, CI-built, **no Flux image automation**, so bump the tag by hand, in step with the Pi) + an nginx sidecar (the patched `127.0.0.1:30500/nginx` image) that serves `/indi-allsky/images` straight from the images PVC and proxies the rest. `allsky-db` MariaDB 11.8 StatefulSet. Static Retain PVs at `/mnt/md0/k8s/indi-allsky-{db,images,state}`: images is 150Gi RWX (≈75 GB steady state), state is the Flask-Migrate folder at `/var/lib/indi-allsky` (start_gunicorn.sh autogenerates and applies a revision on every start). gunicorn needs privilege escalation (its entrypoint `sudo chown`s). Nightly `allsky-expire` CronJob (12:00 Europe/London) runs `expire.sh` (images 30 d, videos 365 d), since a SyncAPI receiver never expires anything itself. `allsky.k8s.ecafe.org`, internal only on default web/websecure; the Pi uses `https://allsky.k8s.ecafe.org/indi-allsky` with cert verification off. **Public, read-only gallery at `https://zephyr.ecafe.org`** (tm `4ad5606d`): `allsky/public-ingressroute.yaml` is an IngressRoute on `publictls` only (router 443 → master:8445 → `kube-system/traefik-publictls-alt` → `publictls`) that allowlists GET/HEAD on the no-login views only, so login, SyncAPI, admin/config and every POST 404 there (re-check the allowlist when the image's upstream commit moves); cert `allsky/zephyr.ecafe.org-production` (HTTP-01, CoreDNS `zephyr.override` for the hairpin); http:// redirects to https. **`/` is a landing page** (`allsky/zephyr-site/index.html`, a `configMapGenerator` ConfigMap mounted into the nginx sidecar; master copy in `~/projects/allsky/zephyr-site/`) and **`/weather.json` is proxied by nginx to the garden WeeWX Pi, `http://192.168.0.220/weewx/zephyr/weather.json`** (weatherstation.local, standalone, not a node; it's a DHCP client, so the cluster depends on the router keeping it at .220), both on the public allowlist (tm `c2ac591f`, 2026-11-19). **`allsky-meteors` CronJob** (`*/10`, Forbid, tm `a2316080`, 2026-11-23): meteor scorer (`ghcr.io/ennui2342/allsky-meteors:<tag>`, public repo `ennui2342/allsky-meteors`, CI-built, no Flux image automation), read-only on the DB (app user) and the images PVC (fsGroup 10001), writes sqlite + JPEG crops to its own static Retain RWX PV `/mnt/md0/k8s/indi-allsky-meteors` (5Gi, kept off the images PV so `allsky-expire` never touches it); config `meteors.json` + `detect_mask.png` from `allsky/meteors-config/` (configMapGenerator; site location, so not in the public repo); daily outbound HTTPS to celestrak.org for TLEs. Added 2026-11-18 (tm `2ebdb42c`). |
| `botkube` | botkube | `botkube/` | Flux HelmRelease; Discord alerts + kubectl/helm/flux executors |
| `cert-manager` | cert-manager | `cert-manager/` | Flux HelmRelease (v1.x.x); ClusterIssuer for ecafe.org |
| `default` | mosquitto | `mosquitto/` | MQTT broker, anonymous access, port 31883 (NodePort) |
| `default` | mdns-repeater | `mdns/` | Worker-only DaemonSet (master's own repeater removed 2026-08-22 during the flat-network migration — see git history — its sole job was bridging mDNS between master's two old physically-separate interfaces (private worker subnet + main LAN Wi-Fi), which no longer exist now that every node shares one flat switch; mDNS multicast works natively within a single broadcast domain, so nothing replaces it) repeating mDNS packets between the pod network (`cni0`) and the host's physical interface (`eth0`) so mDNS-discoverable devices stay visible to pods regardless of network topology; `hostNetwork: true`, `privileged: true`; image `127.0.0.1:30500/mdns-repeater:latest-patched` (locally patched, served from the local registry, `imagePullPolicy: IfNotPresent`) |
| `default` | modpoll | `solar/` | Reads FoxESS inverter via Modbus at 192.168.0.188, publishes to `solar/foxess` on MQTT |
| `default` | nfs-provisioner | `nfs/template.yaml` | NFS subdir external provisioner |
| `default` | syncthing | `syncthing/` | SyncThing file sync; config + data on NFS |
| `default` | webdav | `webdav/` | hacdias/webdav server for Zotero PDF attachment sync; 20Gi NFS PV; `webdav.k8s.ecafe.org` ingress (internal/Tailscale, used by desktop Zotero) plus a Tailscale-operator Funnel Ingress (`webdav-funnel`) giving a trusted `*.ts.net` cert that works identically on-LAN and off — needed because Zotero for Android refuses self-signed/internal certs and the epigone.ecafe.org path hit home-router NAT-hairpin issues when accessed from inside the LAN; basic-auth user `zotero`, bcrypt password in `webdav-secret.yaml` |
| `default` | web | `website/` | nginx + PHP-FPM StatefulSet; serves k8s.ecafe.org. The landing page `index.html` lives in git (`website/site/index.html`, `website-index` configMapGenerator subPath-mounted over `/usr/share/nginx/html/index.html` in the nginx container, tm `5e7d2b5e`, 2026-11-25): edit it there, not on the volume. Everything else on the `web-data` NFS volume (`favicon.svg`, `/zephyr/`, ...) is still served from the volume |
| `epigone` | epigone routing | `epigone/` | Owns the `epigone.ecafe.org` cert-manager Certificate + Traefik IngressRoute for Home Assistant. Kept as its own namespace (decoupled from home-assistant) since it was briefly shared with webdav too; webdav now uses Tailscale Funnel instead (see below), so this currently only fronts Home Assistant, but stays separate in case another service needs the same public hostname later. |
| `freshrss` | freshrss | `freshrss/` | Self-hosted RSS reader, replacing Feedly — phase 1 of a Readwise Reader self-hosted evaluation (see `linkding`/`wallabag` below for the other phases). NFS-backed data + extensions PVCs; `rss.k8s.ecafe.org` ingress plus a Tailscale ingress for PWA/app installability testing. Custom `User-Agent` override (see recent commits) to fix bot-blocked feeds. Runs a locally-patched image (`127.0.0.1:30500/freshrss:1.31.0-patched-20261124`, see `trivy/patched-images.yaml`), upstream 1.31.0 plus a trixie-security dist-upgrade (zlib1g CVE-2026-85091). |
| `home-assistant` | homeassistant | `home-assistant/ha-*.yaml` | HA 2026.11 (local fork `127.0.0.1:30500/home-assistant:2026.11-patched-20261110`; HACS is now the built-in Marketplace), ClusterIP Service (not `hostNetwork` — corrected 2026-07-29, `ha-deployment.yaml` doesn't set it, only the `mdns-repeater` DaemonSet in this repo does), config on NFS; reachable at `home-assistant.k8s.ecafe.org` and, via `epigone/`, at `epigone.ecafe.org` |
| `home-assistant` | ring-mqtt | `ring-mqtt/` | Ring doorbell → MQTT bridge, RTSP port 30002. `config.json` is a `configMapGenerator` (`ring-mqtt/config.json`, no secrets) subPath-mounted read-only over `/data/config.json` — ring-mqtt in docker runmode has no env-var override for it. `mqtt_url` points at the **in-cluster broker Service** (`mqtt://mosquitto.default.svc.cluster.local:1883`), not the `k8s.ecafe.org:31883` NodePort: the CoreDNS override resolves `k8s.ecafe.org` to Traefik's ClusterIP for pods, which doesn't serve MQTT — that silently broke the Ring→HA doorbell-notification path from 2026-08-22 to 2026-09-09. The Ring OAuth token (`ring-state.json`) stays on the PVC, not in git. |
| `home-assistant` | predbat | `predbat/` | Predbat battery planner (springfall2008/batpred, plain upstream container `nipar44/predbat_addon:v9.10.0`, amd64+arm64). **No Flux image automation on purpose**: Predbat ships several releases a week, so bump the tag by hand, deliberately. Config of record is `predbat/apps.yaml` in `github.com/ennui2342/home-energy` (`~/projects/home-energy/`); `predbat/apps.yaml` here is a copy (`configMapGenerator`, subPath-mounted read-only at `/config/apps.yaml`). Talks to the FoxESS inverter only through HA's API (`http://homeassistant-service.home-assistant.svc:8123`, its own HA long-lived token `predbat`). **In Control of the inverter since 2026-11-25 19:01** (`select.predbat_mode` = 'Control charge & discharge'; deployed in Monitor mode earlier that day, tm `9c862742`, cutover a manual, watched step with Mark per home-energy `predbat/CUTOVER.md`). Never change `select.predbat_mode` or any `switch.predbat_*` from an automated session. A Deployment restart is safe (it resumes in the same mode within a minute), but avoid restarting in the 02:00-05:00 / 16:00-19:00 UK charge and peak-export windows. `apps.yaml` uses explicit Octoplus event entity ids, not regexes (a regex that can't match at startup is disabled until restart, batpred #6299). `Recreate`, 1 replica (never two Predbats). Working dir `/config` on a static Retain PV `/mnt/md0/k8s/predbat-config` (2Gi; the entrypoint copies its Python files in on first start). Web UI at `predbat.k8s.ecafe.org` (internal only, **HTTPS-only** on websecure with Traefik's default self-signed cert; plain HTTP on `web` only 302-redirects to https://, tm `3d46c670`) has a login since 2026-11-25 for its settings pages (`web_username: admin`, `web_password` in `predbat-secrets`; HTTP Basic auth, hence the redirect) and can change settings: never put it on `public`/`publictls`. Requests 512Mi, limit 2Gi |
| `isfdb` | isfdb-mirror | `isfdb/` | Self-hosted mirror of the Internet Speculative Fiction Database (ISFDB) — MariaDB StatefulSet (NFS PVC) seeded from ISFDB's weekly "5.5-compatible" MySQL backup, fronted by a small adapter service (`isfdb-adapter`, custom image `127.0.0.1:30500/isfdb-mirror:<tag>`, served from the local registry) exposing ISBN/title/series/author lookups as JSON at `isfdb-adapter.k8s.ecafe.org` (internal DNS only). A weekly CronJob (`isfdb-refresh`, Sunday 08:00 UTC) lists ISFDB's public shared Backups Google Drive folder for the newest 5.5-compatible dump (no login; replaced the old ISFDB wiki scrape after the wiki started blocking `cloudscraper`, isfdb-adapter `307538f`), downloads it (`gdown`), and atomically swaps it into the live DB only after a row-count sanity check — a failed refresh leaves last week's data live. As of 2026-08-19, the refresh job also posts run-start/complete/failure notifications to Discord (an incoming webhook to `#homelab` since 2026-11-25, previously opsimath's bot) — see the `isfdb-secret.yaml` entry below — giving visibility into *when* a run starts (before the ~20+ minute DB-load window), not just eventual success/failure. Originally built to back a self-hosted ISFDB metadata provider for `librarium/` (permanently removed from this cluster 2026-08-22 — see git history); still actively consumed by `opsimath/` (see that entry — reaches it via `isfdb-adapter.isfdb.svc.cluster.local:8080`), since ISFDB has no public API and Open Library/Google Books/Hardcover are too sparse for older or small-press SFF editions. **The adapter's source lives at `~/projects/isfdb-adapter/`** (public repo `ennui2342/isfdb-adapter`, its own reference implementation) — not in this repo. See `RUNBOOK.md`'s "ISFDB mirror" section for the clone/build/import rebuild steps. |
| `linkding` | linkding | `linkding/` | Self-hosted bookmark manager ("pinboard" — see the `pinboard` Claude Code skill), at `pinboard.k8s.ecafe.org` plus a Tailscale ingress for PWA installability. A CronJob (`linkding-task-sync`) polls linkding for bookmarks tagged `-task`, creates a corresponding `tm` task (`<cli.linkding-task-sync` provenance) for each, then strips the tag so the bookmark isn't re-processed — task lifecycle then belongs entirely to `tm`, no separate dedupe/auto-close bookkeeping in the sync job itself. |
| `mg-reporting` | mg-reporting | `mg-reporting/` | Competitor Watch for Chance & Counters (tm `ab70cca6`): a **worker-only** Rails 8.1 + Solid Queue app — no web server, no Service for the app, no Ingress — plus a dedicated Postgres 18 StatefulSet (`mg-reporting-db`, same shape and patched image as opsimath's, static Retain PV at `/mnt/md0/k8s/mg-reporting-db`). The worker's container sets `args: ["bin/jobs"]`, **not** `command:` — the image's `docker-entrypoint` runs `db:prepare` before `bin/jobs`, and `command:` would replace that ENTRYPOINT and skip it. **PRIVATE repo and PRIVATE image** (commercially sensitive, unlike Mark's other projects): `ghcr.io/ennui2342/mg-reporting` is pulled with a `ghcr-pull` imagePullSecret in-namespace, and Flux's `ImageRepository` authenticates with `flux-system/mg-reporting-ghcr` (both a read:packages-only PAT). CI-built, Flux image automation (`flux-system/mg-reporting-image-automation.yaml`, its own `ImageUpdateAutomation` scoped to `./mg-reporting`). The worker was first committed with `replicas: 0` so the production DB could be loaded from dev before the first scheduled collector run (06:20 Europe/London daily) — done 2026-11-11 (tm `05600a16`: `pg_dump` of dev's `app_development` only, restored as `app_production`, `ar_internal_metadata.environment` set to `production`), now `replicas: 1`. Keep it at exactly 1 (single Solid Queue supervisor, `Recreate` strategy). **App source lives at `~/projects/mg-reporting/`** (private repo `ennui2342/mg-reporting`). |
| `monitoring` | cve-scanner | `trivy/` | Weekly Trivy scan → dedupes/files/auto-closes `tm` tasks; see CVE Patch Management below |
| `monitoring` | grafana | `prometheus/helmrelease.yaml` | grafana.k8s.ecafe.org, anonymous viewer access; managed by kube-prometheus-stack chart |
| `monitoring` | health-monitor | `health-monitor/` | CronJob, 30min: Flux Kustomization/HelmRelease failed-or-stalled checks (the only kubectl-based check left — CrashLoopBackOff/PVC/Node checks were removed 2026-07-27, now redundant with kube-prometheus-stack's default rules) **plus bridges every firing Alertmanager alert into a `<cli.cluster-health` `tm` task** (dedup/close on the alert's own fingerprint) — see Monitoring & Alerting below |
| `monitoring` | home-energy-monitor | `home-energy/` | Daily CronJob (06:15 Europe/London, `Forbid`, TTL 604800) running `ghcr.io/ennui2342/home-energy:<tag>` (public image, stdlib Ruby, CI-built as `1.YYYYMMDD.RUN`; Flux image automation `flux-system/home-energy-image-automation.yaml`, its own `ImageUpdateAutomation` scoped to `./home-energy`). Added 2026-11-25 (tm `3f408bfa`). Daily: Octopus tariff/rate-change check, records the HA solar-forecast snapshots and yesterday's PV + peak import into InfluxDB `telegraf.energy_5y` (measurements `monitor_rates`, `forecast_daily`, `pv_daily`, `peak_daily`); on the 1st, a monthly model-vs-meter report (`monthly_report` + Discord). **Reads** InfluxDB `energy_5y.foxess_30m` (from `cq_foxess_30m`, RUNBOOK "InfluxDB retention policies"), HA REST at `http://homeassistant-service.home-assistant.svc:8123` (in-cluster Service DNS) and the Octopus API (outbound HTTPS); writes nothing to HA or the inverter. Posts to its own Discord webhook only on events/anomalies/failures (exits non-zero on failure, so `KubeJobFailed` → health-monitor task too). Pod sets `runAsUser: 10001` because the image's `USER app` is non-numeric and `runAsNonRoot` can't otherwise be verified. **App source lives at `~/projects/home-energy/`** (repo `ennui2342/home-energy`). |
| `monitoring` | influxdb | `monitoring/influxdb.yaml` | InfluxDB 1.8.0, 8Gi NFS PV |
| `monitoring` | kube-prometheus-stack | `prometheus/` | Flux HelmRelease (70.x.x); Prometheus + Alertmanager + Grafana + node-exporter + kube-state-metrics. Alertmanager → Discord routing exists (`prometheus/helmrelease.yaml`) but was silently broken from when it was first configured until 2026-07-27 (this Alertmanager version doesn't support `discord_configs`' `webhook_url_file`, so every operator reconcile failed — fixed via `HelmRelease.spec.valuesFrom` injecting the secret value directly instead). Discord messages use a compact custom template (`alertmanager.templateFiles` `discord.tmpl`: summary + description for one alert, one line per alert for several, capped at 10, no label/Source dumps), and `namespace="allsky"` alerts group per namespace so one camera Pi fault sends one message |
| `monitoring` | nas-monitor | `nas-monitor/` | CronJob, 15min: SSH to the NAS, parse `/proc/mdstat`, Discord alert on RAID degradation; SSH key also reused by `pvc-usage-monitor` |
| `monitoring` | nas-diskio-monitor | `nas-diskio-monitor/` | CronJob, `*/5`: SSHes to the NAS as a dedicated low-privilege account (`k8s-monitor`, its own `nas-diskio-ssh-key` secret — *not* `nas-monitor`'s key or account), reads `/proc/diskstats` for `sdb`/`sdc`/`md0` and writes raw cumulative counters straight to InfluxDB line-protocol (`nas_diskio` measurement, `nas_30d` RP), bypassing telegraf. Added 2026-08-23 while investigating repeated `NodeHighIOWait` alerts (tm task `50cad5c2`) — this NAS's embedded net-snmp 5.4.4 doesn't compile in the UCD-DISKIO-MIB module, so there's no SNMP path for NAS disk I/O. `activeDeadlineSeconds: 120`, `backoffLimit: 2`, `ttlSecondsAfterFinished: 3600` (sub-daily, no RWO PVC — see LINT.md) |
| `monitoring` | os-eol-scanner | `os-eol-scanner/` | CronJob, weekly (Mon 07:30): reads each node's `status.nodeInfo.osImage` via the k8s API (no SSH needed) and flags Ubuntu LTS EOL approaching/passed — closes the gap the CVE scanner can't (trivy only scans container images, never the host OS) that let the whole fleet sit on an EOL, unpatched Ubuntu 20.04 for over a year unnoticed (tm task `b914610a`, resolved 2026-08-22 with a full node rebuild). No ESM assumed, since this fleet has never had it attached. Deliberately files tasks **untagged** (no `#~upgrade`/`#~deploy`/`#~health`) — an OS reimage is hardware-touching work like `b914610a` was, not something to auto-route to a specialist; `++ennui2342` for backlog visibility instead |
| `monitoring` | pvc-usage-monitor | `pvc-usage-monitor/` | CronJob, 2h: real per-PVC usage vs. each PVC's own requested size, via `du` over SSH to the NAS (reuses `nas-monitor`'s key) — `kubelet_volume_stats_*` can't do this on this StorageClass, see that directory's script comment. Fires a `<cli.cluster-health` task at 90% of request; `nfs-subdir-external-provisioner` enforces no real quota, so this is a self-imposed budget check, not a hard limit |
| `registry` | registry | `registry/` | `registry:2`, NFS-backed PVC, NodePort 30500, plain HTTP + anonymous (LAN-only, never exposed beyond it). Target for locally-built images, replacing `docker save`/`scp`/`ctr images import` — see `RUNBOOK.md`'s "Local container registry" for the one-time per-node containerd trust config and Mac-side Docker Desktop config this needs (neither is GitOps-managed, both are node/workstation-local). Confirmed live 2026-07-29 (updated 2026-08-01 — `linkding` and `wallabag` forks added since): migration is complete — every custom/forked image in the repo (`mdns-repeater`, `isfdb-mirror`, `mosquitto`, `modpoll`, `home-assistant`, `telegraf`, `ring-mqtt`, `trivy`, `botkube`, `linkding`, `wallabag`, `syncthing`, the Flux controllers, `k8s-toolbox`) is now pulled from `127.0.0.1:30500` with `imagePullPolicy: IfNotPresent`; no manifest in the repo still uses `imagePullPolicy: Never` |
| `monitoring` | loki | `monitoring/loki.yaml` | Flux HelmRelease (6.x.x); log aggregation, 31-day retention, NFS storage. **Ruler enabled** (2026-11-20, tm `1f493a81`): rules come from git as ConfigMaps labelled `loki_rule` (the chart sidecar writes them to `/rules/fake`; e.g. `monitoring/loki-rules-allsky.yaml`), alerts go to the kube-prometheus-stack Alertmanager, so the same Discord route + health-monitor tm bridge as Prometheus alerts. The TSDB active index (`tsdb_shipper.active_index_directory`) is on a memory emptyDir, **not** the NFS PVC: on NFS, Loki deletes head-WAL files it still holds open, the client silly-renames them to `.nfsXXXX`, and the startup WAL cleanup fails fatally (`unlinkat ...: directory not empty`), so every restart crash-looped (hit live 2026-11-20). Don't move it back |
| `monitoring` | syslog-receiver | `monitoring/syslog-receiver.yaml` | LAN syslog → Loki (tm `1f493a81`): single-replica Grafana Alloy (`grafana/alloy`, plain upstream tag, chosen over EOL promtail), RFC 5424 over TCP on **NodePort 30514** (any node IP; the all-sky camera Pi sends to `192.168.0.8:30514`). LAN-only: not forwarded by the router, not on Tailscale (the Connector advertises only pod/service CIDRs). Labels `job=syslog`, `host`, `facility`, `severity`, `app` (mapped from facility for the indi-allsky daemons: local6 → `indi-allsky`, local5 → `indiserver`, local7 → `indi-allsky-web`, local4 → `indi-allsky-upgrade`, kern → `kernel`, else APP-NAME). Feeds the `Allsky*` Loki alerts; see RUNBOOK's "All-sky camera log alerts" for testing and silencing |
| `monitoring` | promtail | `monitoring/promtail.yaml` | Flux HelmRelease (chart pinned `6.17.x`); ships pod logs to Loki. Runs a locally-patched image (`127.0.0.1:30500/promtail:3.6.11-patched`, see `trivy/patched-images.yaml`) via `values.image` override — promtail is fully EOL upstream (deprecated in favor of Grafana Alloy, commercial support ended 2026-02-28), `grafana/promtail:3.6.11` is the last image Grafana will ever publish for it, and the `promtail` Helm chart hasn't had a release since 6.17.1 (still `appVersion: 3.5.1`), so there's no plain upstream tag or chart bump that can ever resolve OS-package CVEs here again |
| `monitoring` | telegraf | `monitoring/telegraf.yaml` | Scrapes MQTT (mosquitto.default:1883), statsd, SNMP (NAS at 192.168.0.76) |
| `opsimath` | opsimath | `opsimath/` | Rails 8.1 / Ruby 4.0 app (tm ticket `748e2eac`) — web (Puma via Thruster) + a Solid Queue worker (no Redis/Sidekiq) + a dedicated Postgres 18 instance, all in-namespace. Syncs a Goodreads "to-read"-style feed and posts Discord notifications; reaches `isfdb-adapter` over in-cluster Service DNS (`isfdb-adapter.isfdb.svc.cluster.local:8080`) — deliberately not the public Traefik hostname, which resolves inconsistently depending on whether Tailscale's DNS resolver is in a given client's path. `opsimath.k8s.ecafe.org` ingress (HTTP-only — `router.entrypoints: web` annotation, since there's no TLS cert for this host; serving it on `websecure` with Traefik's self-signed default cert let a `Secure` `_app_session` cookie + a zone-wide `includeSubDomains` HSTS header get cached in browsers, which then broke plain-HTTP login with a permanent CSRF-422 redirect-to-login loop the app-side `force_ssl` carve-outs couldn't fix — 2026-09-02) plus a Tailscale ingress for the user's own remote access. Active Storage (cover images) PVC is `ReadWriteMany`, not this repo's usual `ReadWriteOnce` — web and worker are separate Deployments both needing concurrent write access, since Goodreads sync (which attaches covers) runs on the worker. Also runs `opsimath-cover-compare` (tm task `b54a5adc`), a stateless Python/FastAPI ORB+RANSAC image-similarity sidecar Deployment (no DB, no secrets, no persistent storage, ClusterIP-only, no Ingress) called by the worker over in-cluster Service DNS during Goodreads enrichment. **App source lives at `~/projects/opsimath/`, not in this repo** (public repo `ennui2342/opsimath`) — this repo only has the deployment manifests. Unlike isfdb-adapter/librarium's manual local-registry builds, opsimath is fully automated (`taskmgt/`-style): its own CI pushes versioned tags to `ghcr.io/ennui2342/opsimath` and `ghcr.io/ennui2342/opsimath-cover-compare`, and Flux image automation (`flux-system/opsimath-image-automation.yaml`, a single `ImageUpdateAutomation` covering both images) redeploys automatically — see `RUNBOOK.md`'s "opsimath" section for the from-scratch-rebuild fallback only. |
| `system-upgrade` | system-upgrade-controller | `system-upgrade/` + `k3s-upgrade/` | rancher/system-upgrade-controller v0.20.2 (upstream manifests vendored in `system-upgrade/upstream/`, kustomize-patched to the repo's soft worker affinity, with no control-plane tolerations). Executes the `Plan`s in `k3s-upgrade/plans.yaml`, the cluster's declared k3s version, as privileged Jobs on each node. The `server-plan` Job is the one deliberate control-plane toleration in the repo (it has to run on master, since it upgrades it). Privileged + hostPath by design; no network policy (same as the rest of the cluster). Added 2026-10-24 for the 1.32 → 1.36 upgrade (tm 24344397). |
| `tailscale` | operator | `tailscale/` | Flux HelmRelease (1.x.x); `ts-k8s-connector` exposes taskmgt frontend; also runs the Funnel proxy for webdav (`ts-webdav-funnel` StatefulSet, auto-created from `webdav/funnel-ingress.yaml`) |
| `taskmgt` | api + frontend | `taskmgt/` | Task management app; see Flux image automation below |
| `wallabag` | wallabag | `wallabag/` | Self-hosted read-it-later app, replacing Instapaper — phase 1 of the Readwise Reader self-hosted evaluation alongside `freshrss`. NFS-backed data + images PVCs; `later.k8s.ecafe.org` ingress plus a Tailscale ingress for PWA installability testing. Runs plain upstream `wallabag/wallabag:2.6.19` (Alpine 3.24 + PHP 8.3, no Flux image automation, bump by hand); the 2026-10-24 to 2026-11-25 local php84 fork was retired once upstream shipped Alpine 3.24 with `session.upload_progress` off (tm `38a8a4ab`). |

### Off-cluster: Frigate NVR on the Mac Studio

Frigate is **not** on the cluster: it runs in Docker Desktop on the Mac Studio (compose project
`/Volumes/SSD/sync/projects/frigate/`, local-only git repo, UI `http://mac-studio.local:5001/`,
go2rtc RTSP restream on the Mac's `:8554`). Live since 2026-07-16. It depends on two cluster NodePorts
on master: ring-mqtt's RTSP restream (`192.168.0.8:30002`) and mosquitto (`192.168.0.8:31883`),
and HA consumes it through the `frigate` custom integration (in HA's `custom_components`). So
changing those NodePorts, or moving ring-mqtt/mosquitto, breaks Frigate and HA's driveway alerts.

**Why not on the cluster** (reconstructed 2026-11-28, not recorded at the time; Mark recalls
"processing / ARM"): every node is a Raspberry Pi 4 (4 cores, 8 GB, arm64) with no detector
accelerator (no Coral, no GPU Frigate can use), and Frigate's object detection plus ffmpeg decode
is CPU-heavy (the config uses `detectors: cpu` with 4 threads). That load on Pi 4s would
compete with everything else and with the NFS-latency-sensitive workloads. Before proposing a move
to the cluster, solve the detector (e.g. a USB Coral on a worker) first.

### Key Ingress Hostnames
- `k8s.ecafe.org` — website
- `syncthing.k8s.ecafe.org` — SyncThing web UI, internal DNS only
- `home-assistant.k8s.ecafe.org` — Home Assistant (internal DNS only)
- `isfdb-adapter.k8s.ecafe.org` — ISFDB mirror adapter JSON API, internal DNS only
- `epigone.ecafe.org` — public hostname for Home Assistant (TLS via cert-manager, real Let's Encrypt cert), routed by `epigone/`'s IngressRoute
- `grafana.k8s.ecafe.org` — Grafana
- `allsky.k8s.ecafe.org` — indi-allsky all-sky camera gallery + SyncAPI receiver (internal DNS only; the camera Pi uploads to `/indi-allsky` over HTTPS with Traefik's default cert, verification off)
- `rss.k8s.ecafe.org` — FreshRSS (also on Tailscale, for PWA installability off-LAN)
- `pinboard.k8s.ecafe.org` — linkding bookmark manager (also on Tailscale as `pinboard.tail611131.ts.net`)
- `predbat.k8s.ecafe.org` — Predbat battery-planner web UI, internal DNS only, HTTPS-only (http:// redirects; Basic-auth login only: never expose publicly)
- `later.k8s.ecafe.org` — wallabag read-it-later (also on Tailscale, for PWA installability off-LAN)
- `opsimath.k8s.ecafe.org` — opsimath (also on Tailscale as `opsimath.tail611131.ts.net`), for the user's own remote access
- `tasks.k8s.ecafe.org` — taskmgt frontend (also on Tailscale as `taskmgt`)
- `webdav.k8s.ecafe.org` — WebDAV server, internal/Tailscale access (used by desktop Zotero)
- `webdav.tail611131.ts.net` — WebDAV server via Tailscale Funnel (`webdav/funnel-ingress.yaml`), trusted cert, works on-LAN and off (used by Zotero for Android); root URL, no path suffix. Required two one-time settings in the Tailscale admin console (not managed in this repo): "HTTPS Certificates" enabled (DNS tab) and the `funnel` node attribute granted to `tag:k8s` in the ACL policy
- `zephyr.ecafe.org` — PUBLIC read-only all-sky gallery (`allsky/public-ingressroute.yaml`, publictls via router 443 → master:8445, real Let's Encrypt cert). Still a CNAME to the `ennui2342.ddns.net` DDNS name; no longer served by `website/`

### Traefik Customization
The k3s-bundled Traefik is customized via `traefik/helmchartconfig.yaml` (a `HelmChartConfig`
targeting the `traefik` HelmChart k3s manages in `kube-system`) to set
`--providers.kubernetescrd.allowCrossNamespace=true`, required for the `epigone/` IngressRoute
to reference the `homeassistant-service` Service in the `home-assistant` namespace. Applying this restarts the Traefik pod
(brief downtime for all ingress hostnames).

The same file defines the internet-facing entry points `public` (:8081) and `publictls` (:8444),
the only entry points the router forwards to (2026-10-24). `traefik/publictls-alt-service.yaml` exposes
`publictls` on a second port, :8445 (router 443, for zephyr.ecafe.org), since the router won't take two
rules to 8444; a separate Service so the HelmChartConfig, and Traefik, stay untouched. `web`/`websecure` are `asDefault`, so a route
is public only if it explicitly names `public`/`publictls`. See RUNBOOK's "Router port forwards".

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
- `allsky/allsky-secret.yaml` — `allsky-secrets`: `MARIADB_ROOT_PASSWORD`/`MARIADB_PASSWORD`, `INDIALLSKY_FLASK_SECRET_KEY`, `INDIALLSKY_FLASK_PASSWORD_KEY` (a Fernet key that encrypts stored secrets such as API keys in the DB: **never change it** once set, or every stored API key becomes unreadable) and `INDIALLSKY_WEB_PASS`, the first web admin's (`ennui2342`) bootstrap password. All generated 2026-11-18. The SyncAPI user's API key is deliberately **not** stored here: it lives only in the DB (encrypted) and on the Pi
- `flux-system/discord-webhook-secret.yaml` — Discord webhook for Flux notifications (`#homelab`; see Discord Notifications for all three `discord-webhook` copies)
- `syncthing/discord-webhook-secret.yaml` — Discord webhook for SyncThing conflict monitor
- `nas-monitor/discord-webhook-secret.yaml` — creates `discord-webhook` in the `monitoring` namespace; despite living in `nas-monitor/`, this is the shared secret `health-monitor`, `trivy`, and `pvc-usage-monitor` also read (each just references it by name, no separate copy) — don't assume it's NAS-specific or safe to remove if `nas-monitor` is ever decommissioned
- `nas-monitor/nas-ssh-key-secret.yaml` — SSH key for the NAS (port 9222), used by both `nas-monitor` (RAID monitoring) and `pvc-usage-monitor` (per-PVC `du`) — same multi-consumer caveat as above
- `nas-diskio-monitor/nas-ssh-key-secret.yaml` — creates `nas-diskio-ssh-key` in `monitoring`: a *separate* SSH key for a dedicated low-privilege NAS account (`k8s-monitor`, port 9222), used only by `nas-diskio-monitor` to read `/proc/diskstats`. Deliberately not the `nas-monitor`/`pvc-usage-monitor` shared key or its account — narrower blast radius for the metric-only diskstats read
- `webdav/webdav-secret.yaml` — hacdias/webdav config.yaml, contains bcrypt-hashed basic-auth password for the `zotero` user
- `tailscale/operator-oauth-secret.yaml` — Tailscale OAuth client ID + secret
- `prometheus/grafana-admin-secret.yaml` — Grafana admin username + password
- `isfdb/isfdb-secret.yaml` — MariaDB root password, plus `DISCORD_WEBHOOK` (the `#homelab` incoming webhook) for `refresh.py`'s run-start/complete/failure notifications. Until 2026-11-25 this held opsimath's bot token + a channel ID instead; switched because the job only posts, and a webhook can do nothing else
- `botkube/botkube-secret.yaml` — botkube's Helm `values.yaml` (contains botkube's Discord bot token and its `#homelab` channel ID)
- `freshrss/freshrss-secret.yaml` — `FRESHRSS_INSTALL`/`FRESHRSS_USER` bootstrap admin credentials
- `linkding/linkding-secret.yaml` — `LD_SUPERUSER_NAME`/`LD_SUPERUSER_PASSWORD`/`LD_SUPERUSER_EMAIL` bootstrap admin credentials
- `linkding/linkding-api-secret.yaml` — creates `linkding-api-token`, linkding's own API token, consumed by the `linkding-task-sync` CronJob
- `wallabag/wallabag-secret.yaml` — `SYMFONY__ENV__SECRET` app secret
- `home-energy/home-energy-secret.yaml` — `home-energy-secrets` in `monitoring`: `OCTOPUS_API_KEY`, `OCTOPUS_ACCOUNT`, `HA_ACCESS_TOKEN` (an HA long-lived token, read-only use), `DISCORD_WEBHOOK` (the monitor's own webhook). Added 2026-11-25
- `predbat/predbat-secret.yaml` — `predbat-secrets` in `home-assistant`: one key, `secrets.yaml` (Predbat's `!secret` file: `ha_key: <HA long-lived token named 'predbat'>` and `web_password` for the web UI login, added 2026-11-25), mounted at `/secrets` with `PREDBAT_SECRETS_FILE=/secrets/secrets.yaml`. Added 2026-11-25
- `mg-reporting/mg-reporting-secret.yaml` — `mg-reporting-secrets`: `APP_DATABASE_PASSWORD` + `SECRET_KEY_BASE` (both generated), plus `GMAIL_USERNAME`/`GMAIL_APP_PASSWORD`/`DIGEST_TO`/`COMPANIES_HOUSE_KEY`/`DISCORD_FEED_WEBHOOK`/`INBOX_URL`/`INBOX_TOKEN` copied from `~/projects/mg-reporting/.env`. No `RAILS_MASTER_KEY` — the app takes everything from env. No model API keys either: `AI_GATEWAY_KEY`/`ANTHROPIC_API_KEY` were removed 2026-11-26 (tm `cfde5935`), since triage, venue profiles and the landscape analysis now run on the Mac, not the cluster. The worker's `checksum/secrets` annotation must be bumped on any change here (envFrom is read only at start)
- `mg-reporting/ghcr-pull-secret.yaml` + `flux-system/mg-reporting-ghcr-secret.yaml` — `docker-registry` pull secrets for the private `ghcr.io/ennui2342/mg-reporting` image (`ghcr-pull` for the pod, `mg-reporting-ghcr` for the Flux `ImageRepository`); username `ennui2342`, password the read:packages-only classic PAT `GHCR_READ_TOKEN` from `~/projects/mg-reporting/.env`. The first private-image pull secrets in this repo
- `opsimath/opsimath-secret.yaml` — `RAILS_MASTER_KEY` (decrypts `config/credentials.yml.enc`, which holds `secret_key_base` plus real Goodreads and Discord bot secrets — never baked into the image or committed anywhere, per the source repo's own `config/master.key`, itself gitignored there too) and `APP_DATABASE_PASSWORD` for the bundled Postgres, plus `DISCORD_WEBHOOK` (the `#opsimath` incoming webhook, from opsimath's gitignored `.env`; replaced the Rails-credentials bot token for notifications 2026-11-25)

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

### Per-app Kustomizations

The root `kustomization.yaml` lists only `flux-system/` and `kustomizations/`. The bootstrap
`flux-system` Kustomization (`gotk-sync.yaml`, `path: ./`, `prune: true`) therefore reconciles
only the Flux system objects plus **one `Kustomization` CR per app directory** — `kustomizations/<app>.yaml`,
each `path: ./<app>`, `prune: true`, `wait: false`, its own `decryption` (SOPS), `interval: 1h`,
and a minimal `dependsOn` graph (infra: `nfs`/`cert-manager`/`traefik`/`coredns`/`tailscale`/`mdns`/`registry`;
`prometheus`+`monitoring` on `nfs`; apps with an NFS PVC on `nfs`; monitoring-namespace CronJobs on
`monitoring`; `epigone` on `cert-manager`+`traefik`). This gives failure isolation (a broken
`wallabag/` manifest no longer blocks `opsimath/`) and per-app deploy events
(`kustomization/opsimath …`, not `kustomization/flux-system …`).

**Adding an app:** create `<app>/` with its own `kustomization.yaml`, add `kustomizations/<app>.yaml`
(copy an existing one, set `path`/`name`/`dependsOn`), and add it to `kustomizations/kustomization.yaml`.
Do **not** add the app dir to the root `kustomization.yaml`.

**The `monitoring` and `home-assistant` namespaces are now in git** (`monitoring/namespace.yaml`,
`home-assistant/namespace.yaml`) — they were unmanaged (created by the original install) until the
per-app split, which needed them to exist for the dependsOn ordering to mean anything.

History: migrated 2026-09-06 (tm `9db56d2e`). The rollout was **not** clean — phase 2 combined the
root trim with flipping `flux-system` to `prune: false` in one commit, but that flip can't take
effect in the same reconcile that introduces it, so `flux-system` pruned ~25 pods / 6 namespaces
before flipping. Recovered (static `Retain` PVs saved most data; registry images re-pushed from the
Mac's Docker cache; isfdb-db reseeded; Prometheus/Loki history lost). **If this is ever redone
elsewhere: land `prune: false` in its own commit, let it reconcile, THEN trim the root.** See
RUNBOOK's "Per-app Kustomizations".

### taskmgt Image Automation

Flux watches GHCR for new image tags and updates `taskmgt/api.yaml` and `taskmgt/frontend.yaml`
automatically on push to this repo.

- **ImageRepository**: watches `ghcr.io/ennui2342/taskmgt-api` and `ghcr.io/ennui2342/taskmgt-frontend`
- **ImagePolicy**: semver filter `1.x.x` (format: `1.YYYYMMDD.RUNNUMBER`)
- **ImageUpdateAutomation**: commits updated image tags back to this repo; Flux then reconciles

Manifests: `flux-system/taskmgt-image-automation.yaml`

### Discord Notifications

**Channel: every homelab ops message goes to `#homelab`** (channel `1575241681689645086`), not
`#general` (moved 2026-11-25). Three routes, all pointed there:
- **The `discord-webhook` secret** (identical copies in `flux-system`, `monitoring` and `default`,
  from `flux-system/`, `nas-monitor/` and `syncthing/`): the Flux relay, Alertmanager (`valuesFrom`),
  health-monitor, trivy, nas-monitor, pvc-usage-monitor, os-eol-scanner, the syncthing conflict
  monitor, master's backup script, and every Mac-side agent-orchestrator specialist (they read
  `monitoring/discord-webhook` at runtime). The URL's source is `DISCORD_HOMELAB_WEBHOOK` in this
  repo's gitignored `.env`. When it changes, update all three copies and bump the relay's
  `discord-webhook/changed` annotation (it reads the URL as an env var).
- **botkube's bot** (channel ID in `botkube/botkube-secret.yaml`), the only bot token left in the
  cluster: it needs one because it takes commands from Discord.
- **isfdb-refresh**: its own copy of the `#homelab` webhook, `DISCORD_WEBHOOK` in
  `isfdb/isfdb-secret.yaml` (moved off opsimath's bot 2026-11-25; update it with the other three).

Prefer an incoming webhook for anything that only posts: a webhook URL can only post to its one
channel, while a bot token can act anywhere the bot can.

Not homelab ops, so deliberately elsewhere: opsimath's own app notifications (`#opsimath`, the
`DISCORD_WEBHOOK` in `opsimath-secrets`), home-energy (`#home`), mg-reporting (`#mg-reports`).

Flux alerts on deployment events via Discord webhook. Manifests: `flux-system/discord-alert.yaml`.
The Provider is `type: generic`, pointing at `flux-system/discord-relay/` (`flux-discord-relay`,
a stdlib-Python Deployment on `k8s-toolbox`, script in a `configMapGenerator` ConfigMap), not Flux's
own `discord` type, which can't be templated and attaches every event's metadata (revision, token
sha256, app-version) as embed fields. The relay batches events for 20s and posts one compact embed,
one line per event (`✅ **opsimath** · Deployment/opsimath-web configured · 4129a52`), failures first.
If the relay is down, Flux notifications are dropped (the pod is covered by the usual Prometheus alerts).
The `Alert`'s `exclusionList` suppresses non-actionable chatter — HelmRepository index polling,
the GitRepository per-commit "stored artifact for commit" line, the per-Kustomization
"Reconciliation finished in Xs" heartbeat (fires on every reconcile; with 33 per-app
Kustomizations that's ~30 no-op heartbeats per push, enough to make Discord rate-limit), and
transient "Dependencies do not meet ready condition". What still comes through: a real change
(`<obj> configured`, now per-app named) and any failure (different message text, unaffected by
the exclusions). A genuinely stalled Kustomization is `health-monitor`'s job (Flux
failed-or-stalled check → `tm` task), not a Discord page.

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
`127.0.0.1:30500/k8s-toolbox:1.36.5-20261024` (source: `k8s-toolbox/Dockerfile` — `alpine/k8s`
base, `apk update && apk upgrade` for current OS packages, plus `openssh-client curl jq python3
py3-yaml`) for any new lightweight CronJob needing these tools; extend that Dockerfile rather than
reaching for `apk add` in a `command:` block. Rebuild + repush with a new date-suffixed tag (same
`kubectl-version-YYYYMMDD` pattern) whenever the weekly CVE scan flags this image or the k3s
version bumps.

## CVE Patch Management

Weekly Trivy scan (`monitoring/cve-scanner` CronJob, Monday 07:00, `trivy/trivy.yaml`) files one
`tm` task per vulnerable image (`+cli.claude-code.k8s <cli.cve-scanner`), deduping on creation and
auto-closing tasks for images no longer flagged. k3s-bundled `rancher/*` images (Traefik,
local-path-provisioner, klipper-lb/helm) are the exception: no standalone bump exists, so instead
of one task each they're folded into the single `#~k3s-upgrade` task (existing human one reused,
§wait preserved; only its `CVE scan`/`BundledCVEHash` lines are rewritten, and only when that
CVE set changes) — they used to be re-filed every Monday and closed as duplicates, burning
nightly orchestrator slots (2026-09-21/28). A Mac-side aswarm pipeline
(`/Volumes/SSD/pipelines/agent-orchestrator.yaml`, renamed 2026-08-19 from `nightly-agents`, then
`k8s-orchestrator` — general-purpose task routing, not k8s-specific, though its only live wiring
today is this repo — runs every 30min, though CVE/health work still only dispatches during the
1am/6am window) works the
queue: an orchestrator selects the highest-priority eligible task and routes it by tag to an
upgrade, health, or deploy specialist subagent. The upgrade specialist's prompt lives at
`~/projects/agents/k8s/upgrade-prompt.md` (its own separate git repo, private `ennui2342/agents` — not part
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
`node-provisioning/` (`52unattended-upgrades-local.conf` + `k8s-gated-reboot.{sh,service,timer}`),
deployed by hand to every node (not GitOps-managed, host-local like the containerd registry
trust config and master's backup cron). unattended-upgrades' own `Automatic-Reboot` is off;
`k8s-gated-reboot.timer` reboots at the node's slot **only if Prometheus shows the cluster
healthy** (all nodes Ready, nothing crash-looping, no Running pod stuck not-Ready, and
kube-state-metrics actually reporting), otherwise holds and posts a `NodeRebootHeld` alert that
health-monitor turns into a task. Added after 2026-11-12, when the old blind timer rebooted all
four nodes onto a kernel (7.0.0-1023) that broke container AppArmor, k8s-1 first and the rest
anyway (tm 17f100eb). **Reboots happen only in the nightly maintenance window, 05:10–05:55, staggered per node (master
05:10, `k8s-1` 05:20, `k8s-2` 05:30, `k8s-3` 05:40), if one's pending** — see "Nightly schedule"
under Scheduling Constraints for the window and what must stay out of it. (Was 04:15–05:00 until
2026-11-26; moved out of the battery's 02:00–05:00 charge window, tm `6687a9cb`.) Staggered
deliberately, not a single shared time: every node runs the identical OS image, so an update
needing a reboot tends to land on all four within the same day or two, and a shared time would
mean the whole cluster going down simultaneously with no cross-node awareness — a smaller-scale
echo of the exact problem this fleet's 2026-08-19/22 rebuild was about. Master first so it's
stable before any worker needs to rejoin it; each node's gate holds if the previous one didn't
come back healthy.

Images with no upstream fix get rebuilt locally and forked (`127.0.0.1:30500/*-patched`,
`imagePullPolicy: IfNotPresent`, pushed to the local registry). Every fork
is tracked in `trivy/patched-images.yaml` alongside a reproducible Dockerfile under
`trivy/patched-images/<name>/`. The same scan also re-checks each fork's plain upstream image
weekly and files a `<cli.reconcile-scanner` task to revert once upstream ships an equivalent fix —
see `RUNBOOK.md`'s "CVE Patch Management" section for the full mechanics.

## Directory Structure Notes

```
kustomizations/   — one Flux Kustomization CR per app dir (path ./<app>, own SOPS decryption, dependsOn) — see Flux Setup > Per-app Kustomizations; root kustomization.yaml lists ONLY flux-system/ + kustomizations/
allsky/           — indi-allsky web/SyncAPI receiver for the garden all-sky camera: gunicorn + nginx-sidecar Deployment, MariaDB StatefulSet, static Retain PVs (db/images/state/meteors), nightly expire CronJob, allsky-meteors scorer CronJob (+ meteors-config/), internal ingress, public read-only zephyr.ecafe.org IngressRoute + Certificate (not `indi-allsky/`, which is a gitignored stale upstream clone)
botkube/          — Flux HelmRelease + Discord webhook secret; Discord alerts + kubectl/helm/flux executors
cert-manager/     — Flux HelmRelease + HelmRepository (jetstack) + ClusterIssuer
coredns/          — CoreDNS override resolving k8s.ecafe.org (apex + subdomains) straight to Traefik's ClusterIP, for Tailscale Split DNS clients — see Cluster Topology's DNS note above
flux-system/      — Flux bootstrap output + SOPS patch + alert config + discord-relay/ (compact Flux→Discord formatter)
dashboards/       — Custom Grafana dashboard ConfigMaps (Solar, Observatory, NAS Monitor, Weather Station)
epigone/          — epigone.ecafe.org namespace: cert-manager Certificate + IngressRoute fronting Home Assistant
freshrss/         — Self-hosted RSS reader (Readwise Reader evaluation, phase 1): deployment, data/extensions PVCs, internal + Tailscale ingress, bootstrap secret
health-monitor/   — CronJob: Flux Kustomization/HelmRelease checks + Alertmanager→tm bridge (see Monitoring & Alerting)
home-assistant/   — HA deployment, service, ingress, PVC
home-energy/      — Daily home-energy-monitor CronJob (monitoring ns; Octopus tariff check + HA forecast/PV/peak records into InfluxDB energy_5y, monthly model-vs-meter report), secret; image via Flux image automation
isfdb/            — Self-hosted ISFDB mirror: MariaDB StatefulSet, adapter Deployment (JSON API over the mirror), weekly refresh CronJob; adapter/ holds the custom image source (Dockerfile, adapter.py, refresh.py)
master-backup/    — k3s-backup.sh, deployed by hand to master (node-local cron, not GitOps-managed) — see RUNBOOK "Master Datastore Backup & Restore"
node-provisioning/ — Host-local config deployed by hand to every node (not GitOps-managed): 52unattended-upgrades-local.conf, 99-k8s-apparmor.conf (sysctl; kernel 1023 AppArmor stacking broke in-container signals 2026-11-12, see RUNBOOK 0f-bis)
k8s-toolbox/      — Dockerfile only, no manifests: shared image for lightweight CronJobs (kubectl + openssh-client/curl/jq/python3/py3-yaml), see Monitoring & Alerting
linkding/         — Self-hosted bookmark manager: deployment, data PVC, internal + Tailscale ingress, bootstrap + API-token secrets, linkding-task-sync CronJob (bookmark→tm bridge)
mg-reporting/     — Worker-only Rails app (private GHCR image): Solid Queue worker Deployment (replicas: 1), bundled Postgres 18 StatefulSet + static Retain PV, GHCR pull secret, app secret
mdns/             — mdns-repeater DaemonSet (worker-only), hostNetwork mDNS relay between pod network and host interface
monitoring/       — InfluxDB, Telegraf, Loki (+ ruler, loki-rules-*.yaml rule ConfigMaps), Promtail, syslog-receiver (Alloy, NodePort 30514); all monitoring stack manifests
prometheus/       — kube-prometheus-stack HelmRelease + HelmRepository + grafana-admin secret + custom PrometheusRule (alerting-rules.yaml)
mosquitto/        — Mosquitto deployment, configmap, service
nas-monitor/      — CronJob: SSH to NAS, parse /proc/mdstat, Discord alert
nas-diskio-monitor/ — CronJob (*/5): SSH to NAS as low-priv k8s-monitor, read /proc/diskstats for sdb/sdc/md0, write straight to InfluxDB (no SNMP path exists for NAS disk I/O) — see Monitoring & Alerting, tm task 50cad5c2
nfs/              — NFS provisioner Helm template
opsimath/         — Rails app: web + Solid Queue worker Deployments, bundled Postgres 18 StatefulSet, RWX Active Storage PVC, internal + Tailscale ingress
os-eol-scanner/   — CronJob: weekly Ubuntu LTS EOL check across all nodes, files/auto-closes tm tasks (untagged, human-only — see CVE Patch Management below)
predbat/          — Predbat battery planner (home-assistant ns, in Control since 2026-11-25): Deployment (Recreate), static Retain PV/PVC, Service, internal HTTPS-only Ingress (+ http→https redirect), apps.yaml configMapGenerator (copy of home-energy's), ha_key secret
pvc-usage-monitor/ — CronJob: real per-PVC usage vs. requested size via NAS-side `du` over SSH (see Monitoring & Alerting)
registry/         — local container registry (registry:2), target for future custom image builds — see RUNBOOK.md
ring-mqtt/        — ring-mqtt deployment, PVC, service
solar/            — modpoll deployment and Modbus configmap
syncthing/        — SyncThing deployment, PVCs, service, ingress, conflict CronJob
system-upgrade/   — rancher/system-upgrade-controller (upstream/ vendored + kustomize patches); executes k3s-upgrade/'s Plans
k3s-upgrade/      — server-plan + agent-plan: the cluster's declared k3s version (bump both, commit) — see RUNBOOK "Upgrading k3s"
tailscale/        — Flux HelmRelease + HelmRepository (tailscale) + Connector CR
taskmgt/          — taskmgt app manifests + Flux image automation
traefik/          — HelmChartConfig customizing k3s's bundled Traefik (allowCrossNamespace, public/publictls entry points) + the publictls :8445 alt LoadBalancer Service
trivy/            — Weekly CVE scanner CronJob; patched-images.yaml tracks custom image forks + reconciliation
wallabag/         — Self-hosted read-it-later app (Readwise Reader evaluation, phase 1): deployment, data/images PVCs, internal + Tailscale ingress, secret
webdav/           — hacdias/webdav deployment, PV/PVC, service, internal ingress, Tailscale Funnel ingress, config secret (Zotero PDF sync)
website/          — nginx/PHP StatefulSet, configmaps, ingress; site/index.html is the landing page source (configMapGenerator)
```

## Orienting a New Claude Instance

1. Run `kubectl get pods -A -o custom-columns='NODE:.spec.nodeName,NS:.metadata.namespace,POD:.metadata.name,STATUS:.status.phase' --no-headers | grep -v Completed | sort` to see live pod placement.
2. Check `kubectl get helmrelease -A` for Flux HelmRelease status.
3. Check `kubectl get gitrepository,kustomization,imagepolicy,imageupdateautomation -A` for Flux status — there are ~35 Kustomizations now (one per app + `flux-system`), not one; `flux get kustomizations` is the readable view.
4. The cluster is the source of truth for what's *running*; this repo is the source of truth for what *should* run.
5. Inactive/historical manifests exist locally but are gitignored — they may be stale.
6. SSH: `ssh ubuntu@k8s.local` (master) or directly to any worker (`192.168.0.81`/`.82`/`.83`) — flat network, no hop required.
7. Use `kubectl` locally — do not SSH to k8s.local just to run kubectl.
