# Cluster Rebuild Runbook

Procedure for rebuilding the homelab k3s cluster from scratch.
The git repo is the source of truth — once Flux is bootstrapped and
the `sops-age` decryption key is in place, everything else is applied
automatically.

## Prerequisites

Tools needed on the Mac:

```sh
brew install kubectl fluxcd/tap/flux age sops
```

Ensure `~/.kube/config` points at the cluster once k3s is up.

---

## Phase 1 — k3s Installation

### Master node

```sh
ssh ubuntu@k8s.local
curl -sfL https://get.k3s.io | sh -
# Copy kubeconfig to Mac
sudo cat /etc/rancher/k3s/k3s.yaml
```

Edit the copied kubeconfig: replace `127.0.0.1` with `k8s.local`, then
save to `~/.kube/config` on the Mac.

### Worker nodes (from master)

```sh
# Get the join token from the master
sudo cat /var/lib/rancher/k3s/server/node-token

# On each worker (k8s-1, k8s-2) via master SSH hop:
curl -sfL https://get.k3s.io | K3S_URL=https://k8s.local:6443 K3S_TOKEN=<token> sh -
```

Verify:

```sh
kubectl get nodes
```

---

## Phase 2 — NFS Storage

The NFS provisioner expects `192.168.0.76:/mnt/md0/k8s` to be exported
and accessible from all cluster nodes. Verify before proceeding:

```sh
ssh ubuntu@k8s.local "showmount -e 192.168.0.76"
```

---

## Phase 3 — Bootstrap Flux

### 3a. GitHub deploy key

Flux needs a write-capable SSH deploy key to push image automation
commits back to the repo.

```sh
# Generate a new keypair (do NOT commit the private key)
ssh-keygen -t ed25519 -f /tmp/flux-deploy-key -N "" -C "flux-system"

# Add the public key to GitHub as a write-capable deploy key:
# https://github.com/ennui2342/k8s/settings/keys
# Key name: flux-system-readwrite
# Allow write access: YES
cat /tmp/flux-deploy-key.pub

# Create the secret in the cluster before bootstrapping
kubectl create namespace flux-system
kubectl create secret generic flux-system \
  -n flux-system \
  --from-file=identity=/tmp/flux-deploy-key \
  --from-file=identity.pub=/tmp/flux-deploy-key.pub \
  --from-literal=known_hosts="$(ssh-keyscan github.com)"
```

### 3b. SOPS age decryption key — MUST be done before Flux reconciles

The age private key lives at `/Volumes/SSD/sync/secure/k8s-flux-age.agekey`.
This must be in the cluster before Flux applies any SOPS-encrypted resources,
otherwise reconciliation will fail on all encrypted secrets.

```sh
kubectl create secret generic sops-age \
  -n flux-system \
  --from-file=age.agekey="/Volumes/SSD/sync/secure/k8s-flux-age.agekey"
```

If the age key file is lost (e.g. new machine without the SSD sync volume mounted),
re-encrypt all `*-secret.yaml` files with a new key before proceeding — see
"Re-keying secrets" below.

### 3c. Bootstrap Flux

```sh
flux bootstrap git \
  --url=ssh://git@github.com/ennui2342/k8s \
  --branch=main \
  --path=./ \
  --private-key-file=/tmp/flux-deploy-key
```

Flux will write `flux-system/gotk-components.yaml` and
`flux-system/gotk-sync.yaml` to the repo (it will push a commit).

---

## Phase 4 — Watch Reconciliation

```sh
flux get kustomizations --watch
kubectl get pods -A
```

All namespaces should come up within a few minutes. Check for failures:

```sh
flux logs --level=error
```

Flux manages the full stack including cert-manager (via `cert-manager/helmrelease.yaml`)
and the Tailscale operator (via `tailscale/helmrelease.yaml`) — no manual Helm installs
needed. cert-manager will begin issuing the `epigone.ecafe.org` TLS certificate
automatically via the `letsencrypt-prod` ClusterIssuer once it is running.
Flux also applies `traefik/helmchartconfig.yaml`, which patches the k3s-bundled Traefik
to enable `providers.kubernetescrd.allowCrossNamespace` (needed by `epigone/`'s
IngressRoute) — this triggers a one-time Traefik pod restart.

---

## Phase 5 — Post-Bootstrap Checks

### Grafana admin password

The admin credentials are in `prometheus/grafana-admin-secret.yaml` (SOPS-encrypted),
applied automatically by Flux. The kube-prometheus-stack chart reads them from the
`grafana-admin` secret — no manual steps needed.

### Grafana dashboards and datasources

Grafana is managed by kube-prometheus-stack (`prometheus/helmrelease.yaml`).

- **Community dashboards** (Node Exporter Full, Kubernetes Cluster, Loki, NFS) are downloaded
  from grafana.com at deploy time via `dashboards.default` in the HelmRelease values.
- **Custom dashboards** (Solar, Observatory, NAS Monitor, Weather Station) are provisioned via
  ConfigMaps in `dashboards/` with label `grafana_dashboard: "1"` — the Grafana sidecar
  picks them up automatically.
- **Datasources** (Prometheus, InfluxDB, Loki) are configured in the HelmRelease values.

To update a custom dashboard: edit in the UI, export the JSON, update the ConfigMap in
`dashboards/dashboard-<name>.yaml`, and commit. The sidecar reloads without a pod restart.

### Tailscale

The operator is deployed via `tailscale/helmrelease.yaml`. OAuth credentials
are read from the SOPS-encrypted `operator-oauth` secret via `valuesFrom` —
no manual steps needed. After the operator pod comes up, approve any new
Tailscale devices in the admin console if they are new machine keys.

### SyncThing

SyncThing config is persisted on NFS (`/mnt/md0/sync/config`), so device
identity and folder config survive a cluster rebuild without any extra steps.
Verify the pod is up and the web UI is reachable at `syncthing.k8s.ecafe.org`.

### Librarium

Postgres data, covers, and media all live on NFS-backed PVCs (`librarium/postgres.yaml`,
`librarium/api-pvc.yaml`), so the book catalog survives a cluster rebuild without any
extra steps — just verify `kubectl get pods -n librarium` comes up healthy and
`librarium.k8s.ecafe.org` (or the Tailscale hostname on `librarium-ts`) loads.

On a genuinely fresh instance (empty database), `REGISTRATION_ENABLED` starts `"true"` in
`librarium/configmap.yaml` so you can create the first admin account through the web UI.
Once that account exists, set `REGISTRATION_ENABLED: "false"`, commit, and:

```sh
kubectl rollout restart deploy/librarium-api -n librarium
```

### ISFDB mirror

Unlike everything else in this repo, `isfdb/adapter-deployment.yaml` and `isfdb/refresh-cronjob.yaml`
reference a **locally built, not-registry-pushed** image (`ghcr.io/ennui2342/isfdb-mirror:local`,
`imagePullPolicy: Never`) — same pattern as `mdns-repeater`, but unlike that one there's no
committed Dockerfile-only fork; the full source lives in this repo at `isfdb/adapter/`. On a
cluster rebuild, before the adapter/CronJob pods can schedule, build and import it on both workers:

```sh
cd isfdb/adapter
docker build -t ghcr.io/ennui2342/isfdb-mirror:local .
docker save ghcr.io/ennui2342/isfdb-mirror:local -o /tmp/isfdb-mirror.tar

scp /tmp/isfdb-mirror.tar ubuntu@k8s.local:/tmp/isfdb-mirror.tar
ssh ubuntu@k8s.local "scp /tmp/isfdb-mirror.tar k8s-1:/tmp/ && scp /tmp/isfdb-mirror.tar k8s-2:/tmp/"
ssh ubuntu@k8s.local "ssh k8s-1 'sudo k3s ctr images import /tmp/isfdb-mirror.tar'"
ssh ubuntu@k8s.local "ssh k8s-2 'sudo k3s ctr images import /tmp/isfdb-mirror.tar'"
```

The MariaDB PVC is empty on a fresh cluster — trigger an initial import manually rather than
waiting for Sunday:

```sh
kubectl create job --from=cronjob/isfdb-refresh isfdb-refresh-manual -n isfdb
```

**This takes 25-35 minutes**, almost entirely spent importing the ~1.6GB uncompressed dump into
NFS-backed MariaDB (`activeDeadlineSeconds: 3600` accounts for this — don't shrink it, an earlier
30-minute budget got killed mid-import on the first live run). A failed/killed run is harmless —
the atomic swap in `refresh.py` only happens after the staging import passes a row-count sanity
check, so it just leaves the mirror empty (fresh cluster) or last week's data (routine refresh)
rather than serving partial data.

The refresh job's login to the ISFDB wiki occasionally gets a transient `403` on the very first
attempt of a session (observed during initial testing; unclear whether it's Cloudflare-side or
something about connection reuse) but succeeds on retry — `backoffLimit: 2` on the CronJob handles
this automatically, no action needed unless it fails 3 times in a row.

### WebDAV (Zotero) — Tailscale Funnel

`webdav/funnel-ingress.yaml` exposes webdav at a stable `*.ts.net` hostname via the
Tailscale operator's Funnel support, used by Zotero for Android (which refuses
self-signed/internal certs). This depends on two **account-level** Tailscale settings
that live outside this repo and outside the cluster, so they are not recreated by a
cluster rebuild — only need to be (re-)done if starting a new tailnet:

- Admin console → **DNS** tab → **HTTPS Certificates** enabled
- Admin console → **Access Controls** → ACL policy grants the `funnel` node attribute
  to `tag:k8s` (the tag the operator's proxies use):
  ```
  "nodeAttrs": [
  	{
  		"target": ["tag:k8s"],
  		"attr":   ["funnel"],
  	},
  ],
  ```

Once both are set, the Ingress's `status.loadBalancer.ingress[].hostname` (`kubectl get
ingress webdav-funnel -n default`) reports the assigned hostname
(`webdav.tail611131.ts.net` at time of writing).

#### Sync-conflict prevention (`.stignore`)

`*.sync-conflict-*` files accumulate when two devices concurrently write files
that SyncThing cannot merge — chiefly **git repositories** (`.git/` internals,
and working trees edited on more than one machine), plus app working-state
(Obsidian workspace, Scrivener caches, SQLite journals) and OS cruft
(`.DS_Store`, `._*`). The `syncthing-conflict-monitor` CronJob only *reports*
the count to Discord; it does not resolve anything.

Prevention is client-side, one `.stignore` per shared-folder root. Because
`.stignore` itself does **not** sync between devices, each folder uses the
shared-include pattern:

- `<folder>/.stignore.shared` — the real pattern list; a normal file, so it
  **does** sync to every device. Edit here; the change propagates everywhere.
- `<folder>/.stignore` — per-device, contains only `#include .stignore.shared`.
  Must be created once on each device (Mac: write the file; Android: paste
  `#include .stignore.shared` into the folder's Ignore Patterns in the app).

**All devices — including the cluster node — use this same include model.** The
cluster's files live on the data PVC (`/data/<folder>/.stignore*` inside the pod
= `/mnt/md0/sync/data/<folder>/` on the NAS). Because those dirs are owned by the
pod user (`abc`/uid 911) and an SSH login (`ennui2342`/uid 2) can't write some of
them, set the cluster's files **from inside the pod as root**:

```sh
POD=$(kubectl get pods -n default -o name | grep syncthing)
# push the current shared file, then point .stignore at it:
kubectl exec -i -n default "$POD" -- sh -c \
  'cat > "/data/Writing/.stignore.shared" && chown abc:abc "/data/Writing/.stignore.shared" && chmod 644 "/data/Writing/.stignore.shared" && printf "#include .stignore.shared\n" > "/data/Writing/.stignore"' \
  < /Volumes/SSD/sync/writing/.stignore.shared    # note: Mac "writing" = cluster "Writing"
```

`.stignore.shared` normally syncs to the cluster on its own, but a slow-scanning
folder (e.g. Morat) may not have received it yet — pushing it via the pod avoids
an `#include` that points at a missing file.

Shared patterns ignore `.git`, OS/editor cruft, and app caches. In the
**projects** folder, `.stignore.shared` additionally lists every git repo that
has a remote (anchored `/repo` lines) so those sync via `git pull/push` instead
of SyncThing. Repos **without** a remote are intentionally left syncing —
SyncThing is their only off-machine backup; give one a remote and add it to the
ignore block to stop it conflicting. Adding an ignore never deletes existing
copies on any device; it only stops further syncing.

#### Default ignore patterns (auto-applied to new folders)

So new folders don't need a `.stignore` created by hand, set SyncThing's
**default ignore patterns** — applied automatically to every folder created
*after* they're set. This is per-device config (`config.xml` → `<defaults>`
→ `<ignores>`), not synced, and only affects folders at creation time
(existing folders are untouched). Set it once on each device.

GUI: **Actions ▾ → Advanced Configuration → Defaults → Ignores**, paste the
lines below, save. Or via REST API (v2.0.14, GUI on `127.0.0.1:8384`):

```sh
KEY=$(grep -m1 -oE '<apikey>[^<]*</apikey>' \
  ~/Library/Application\ Support/Syncthing/config.xml | sed 's/<[^>]*>//g')
curl -s -X PUT -H "X-API-Key: $KEY" -H "Content-Type: application/json" \
  --data '{"lines":[".git","(?d).DS_Store","(?d)._*","(?d).Trashes","(?d).Spotlight-V100","(?d).fseventsd","(?d).apdisk","(?d).#*","(?d)Icon?","(?d).trashed-*",".obsidian/workspace.json",".obsidian/workspace-mobile.json",".obsidian/cache","*.sqlite-journal","*.sqlite-wal","*.sqlite-shm","*.scriv/QuickLook","*.scriv/Files/search.indexes","random_seed","S.gpg-agent*","S.scdaemon","*.sync-conflict-*"]}' \
  http://127.0.0.1:8384/rest/config/defaults/ignores
```

The default patterns are the universal ones only (git internals, OS/editor
cruft, app caches, conflict copies). The projects-folder repo-ignore block is
folder-specific and stays in `projects/.stignore.shared`, not in the defaults.

Two cross-platform gotchas learned the hard way, both now in the shared patterns:

- **`(?d)Icon?`** — macOS custom-folder-icon files are named `Icon` + a trailing
  carriage return (`Icon\r`). That `\r` is an **illegal filename on Android**, so
  a phone can never create it and the folder stays "out of sync" forever. `Icon?`
  (the `?` matches the CR) fixes it. This was the root cause of a multi-day
  "phantom out-of-sync" hunt.
- **`(?d).trashed-*`** — Android 11+ soft-deletes files by renaming them
  `.trashed-<expiry-unixtime>-<name>` (auto-purged ~30 days later). Syncthing
  keeps trying to reconcile these OS-managed files and can't, wedging the folder.

#### Diagnosing SyncThing sync problems (playbook)

Distilled from a long "why won't this folder go green" investigation. Read this
before poking at a stuck folder.

**Accessing the cluster SyncThing.** Its config/data live on NFS PVCs, and the
GUI/REST API run *as the pod*. Two access paths, with a key ownership gotcha:

- **REST API (read state, set ignores, rescan)** — run from inside the pod; the
  API key is in the mounted config:
  ```sh
  POD=$(kubectl get pods -n default -o name | grep syncthing)
  kubectl exec -n default "$POD" -- sh -c '
    KEY=$(grep -oE "<apikey>[^<]*</apikey>" /config/config.xml | sed "s/<[^>]*>//g")
    curl -s -H "X-API-Key: $KEY" http://127.0.0.1:8384/rest/db/status?folder=<ID>'
  ```
- **Filesystem** — SSH is `ennui2342@192.168.0.76 -p 9222`, but that logs in as
  **uid 2**, and the SyncThing data dirs are owned by the **pod user (`abc`/uid
  911)**. So SSH can *read* but often can't *write/delete/rename* under `/data`
  (`Permission denied`), and `sudo` on the NAS needs a password. **For any write
  under `/data`, use `kubectl exec` (root inside the pod) instead of SSH.**
- **busybox gotcha:** the NAS's `find` is busybox — **no `-printf`**. A scan that
  used `-printf` silently produced *zero* results and gave a false "0 conflicts."
  Stick to plain `find … -name '…'` there.

**Useful REST endpoints** (folder IDs from `/rest/config/folders`, device
names from `/rest/config/devices`):

| Endpoint | Tells you |
|----------|-----------|
| `/rest/db/status?folder=ID` | `globalFiles` vs `localFiles`, `state`, `needItems/needDeletes`, `globalBytes`, `ignorePatterns` |
| `/rest/db/completion?folder=ID&device=DEV` | how far a *specific peer* is behind (needItems/needDeletes) |
| `/rest/db/need?folder=ID` | the actual file names the *local* device is missing |
| `/rest/db/ignores?folder=ID` | the loaded+expanded ignore rules (`error:null` = parsed OK) |
| `/rest/db/file?folder=ID&file=PATH` | global vs local version of one file (is it `ignored`/`deleted`?) |

**Lessons that cost the most time:**

- **One unconfigured peer wedges the whole folder.** SyncThing shares a *global
  index*; a single device that still holds `.sync-conflict-*` / `Icon\r` /
  `.trashed-*` files (no ignores set) keeps *announcing* them, so every other
  device shows a residual "out of sync" for phantom files it can't reconcile.
  Fix the laggard, don't chase the symptom on the healthy devices.
- **Editing an `#include`d file does not reload ignores.** SyncThing re-reads
  ignores on a `.stignore` change or a **rescan** — not when the included
  `.stignore.shared` merely changes content. After editing shared patterns,
  **rescan** each folder (or restart) or the new rules won't take effect.
- **A live SQLite DB must never be file-synced** (`zotero.sqlite`, etc.). The
  main file + `-wal/-journal` are only consistent together; Syncthing forks/
  corrupts them. Use the app's own sync (e.g. Zotero account + WebDAV) and ignore
  the DB — attachments (`storage/`) can still ride Syncthing (the "hybrid").
- **Splitting a folder does NOT speed up scans on this hardware.** Scans run in
  parallel (`maxFolderConcurrency: 0` = one per CPU), but `md0` is a **RAID1 of
  two spinning HDDs** — scan cost is seek-bound, and parallel scans just contend
  for the same spindles. To cut scan cost: (a) fewer files (ignore/relocate
  cruft), or (b) scan less often — raise `rescanIntervalS` (fsWatcher already
  catches live changes). Splitting only helps for *per-folder cadence* control.
- **Finding what makes a folder huge:** walk file counts per subtree, e.g.
  `for d in <dir>/*/; do printf '%8s %s\n' "$(find "$d" -type f|wc -l)" "$d"; done | sort -rn`.
  This is how `Morat` (~929k files) was traced to one client subfolder holding
  99.5% of them (dev-cruft-style file explosion).

**Archiving a huge subtree out of a share.** Moving a directory *out* of a share
root is seen by SyncThing as a **mass delete that propagates to all peers**. To
keep it as a NAS-only cold archive, move it to a **top-level path that is not
inside any share root** (folder roots are `/data/<Name>`; `/data/Foo` is not
synced). A same-filesystem move is an **instant rename** (metadata only, zero
copy) — do it via `kubectl exec … mv` (root), not the DSM drag-drop (which
copies). Example already applied: `Morat/gigs/Opportunity Links` (~924k files,
99.5% of Morat) → `/data/Opportunity Links` (unsynced archive), which drops the
Morat scan to a few thousand files. The move *does* delete it from the other
devices — that is expected; the NAS copy is the keeper.

### NAS RAID monitor

The `nas-ssh-key` secret is managed by SOPS. Verify the CronJob exists:

```sh
kubectl get cronjob nas-raid-monitor -n monitoring
```

### InfluxDB retention policies

The `telegraf` database uses two retention policies that must be created
after InfluxDB starts. The NFS volume persists these across pod restarts,
but they must be recreated on a fresh cluster build:

```sh
# Solar/weather data: extend default autogen policy from 24h to 7 days
kubectl exec -n monitoring influxdb-0 -- influx -execute \
  "ALTER RETENTION POLICY autogen ON telegraf DURATION 168h"

# NAS SNMP metrics: separate long-term policy
kubectl exec -n monitoring influxdb-0 -- influx -execute \
  "CREATE RETENTION POLICY nas_30d ON telegraf DURATION 30d REPLICATION 1"
```

---

## Re-keying Secrets

If the age private key is lost and secrets need to be re-encrypted with a
new key:

```sh
# Generate new age key
age-keygen -o "/Volumes/SSD/sync/secure/k8s-flux-age.agekey"

# Note the new public key and update .sops.yaml
# Then re-encrypt all secret files:
find . -name '*-secret.yaml' | while read f; do
  SOPS_AGE_KEY_FILE="/Volumes/SSD/sync/secure/k8s-flux-age.agekey" \
    sops updatekeys --yes "$f"
done
```

---

## Adding a New Secret

```sh
# Create plaintext secret file alongside app manifests, named *-secret.yaml
cat > myapp/mysecret-secret.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: mysecret
  namespace: myapp
type: Opaque
stringData:
  key: value
EOF

# Encrypt in-place (.sops.yaml picks it up automatically)
cd /path/to/k8s && sops --encrypt --in-place myapp/mysecret-secret.yaml

# Add to the app's kustomization.yaml resources list, then commit
```

---

## CVE Patch Management

The `monitoring/cve-scanner` CronJob (Monday 07:00, `trivy/trivy.yaml`) scans the live cluster
weekly with Trivy and files a `tm` task per vulnerable image, tagged `+cli.claude-code.k8s
<cli.cve-scanner`. It dedupes on creation (one task per image, updated in place if the CVE set
changes, auto-closed if the image is no longer flagged) and skips filing tasks entirely for
images already tracked in `trivy/patched-images.yaml` (see below).

A separate aswarm pipeline, `nightly-agents` (`/Volumes/SSD/pipelines/nightly-agents.yaml`, runs
1am/6am on the Mac), works this queue one task at a time: the orchestrator prompt
(`~/projects/agents/k8s/nightly-orchestrator-prompt.md`) selects the highest-priority task and
routes it to the upgrade specialist (`~/projects/agents/k8s/nightly-upgrade-prompt.md` — a
separate, tracked git repo, not part of this one; there was previously also an untracked mirror
under `~/projects/k8s/.claude/` that the orchestrator read from — removed, single source of truth
now). The specialist prefers a plain
upstream tag bump; only builds a custom image when no upstream fix exists.

### Custom-patched images

Some images have no upstream fix available and are patched by rebuilding locally (`docker build`
with an `apk upgrade`/`apt-get upgrade`), then imported directly into containerd on the relevant
node(s) (`ctr image import` or equivalent) and referenced with `imagePullPolicy: Never` — no
registry push required. Every such fork is recorded in `trivy/patched-images.yaml`:

- `strategy: frozen-rebuild` — has a committed Dockerfile under `trivy/patched-images/<name>/`
  capturing the recipe, so it can be reproduced on a from-scratch cluster rebuild instead of
  depending on containerd state that exists only on specific nodes.
- `strategy: live-upgrade` — the manifest runs `apk upgrade` (or similar) at every pod start
  instead of a frozen tag (see `health-monitor/health-monitor.yaml`), for cases where no image
  build is practical. No Dockerfile; reverting means removing the upgrade command.

The same CronJob scans each entry's plain `upstream_image` standalone every week and compares it
against the `critical`/`high` counts recorded at patch time. Once upstream matches or beats that
baseline, it files a `<cli.reconcile-scanner` task — the upgrade specialist treats this as a
revert: switch back to the upstream tag, delete the Dockerfile directory, and remove the
`patched-images.yaml` entry, restoring normal upstream tracking instead of maintaining the fork
indefinitely.

When patching a new image by hand outside the automated flow, add the corresponding entry and
Dockerfile yourself so it doesn't fall off this tracking going forward.
