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

## Physical & Network Topology

The cluster is a physical tower of Raspberry Pi 4Bs sitting on a small
unmanaged switch (Netgear GS305, 5 ports) at the base — not rack-mounted,
just stacked. This section exists because the network design isn't
discoverable from the manifests alone, and got a genuine architecture
review during the 2026-08-19/22 hard-reboot incident (see "Master
Datastore Backup & Restore" below for the reboot itself) and the OS-EOL
hardware-refresh project it's part of (see git history around
2026-08-22 for the full reasoning).

### Original design (used from cluster inception until 2026-08-22)

- Master (`k8s`) was dual-homed: `wlan0` on the main LAN (`192.168.0.8`,
  DHCP), `eth0` as the gateway for a private switch (`192.168.8.1/24`)
  that only the worker Pis (`k8s-1` = `192.168.8.11`, `k8s-2` =
  `192.168.8.12`) plugged into. Master ran `ip_forward=1` plus a
  `MASQUERADE` rule on `wlan0`, i.e. it was a full NAT gateway/router for
  the worker subnet, not just a passive bridge.
- **Why:** master's LAN uplink was Wi-Fi specifically so the *entire*
  tower (master + hub + both workers) could be physically relocated
  anywhere with Wi-Fi coverage and no wired LAN drop needed at the new
  spot — demonstrated directly on 2026-08-22 when it was moved from
  under the stairs to beside the desk mid-incident.
- **The cost, identified 2026-08-22:** this made master a single point of
  failure for *networking*, not just the control plane — if master (or
  just its Wi-Fi link) went down, the workers didn't just become
  unreachable from the Mac, they lost their gateway entirely (no
  internet/main-LAN egress for cert-manager renewals, Discord webhooks,
  etc.). It also meant **every** node's NFS traffic to the NAS
  (`192.168.0.76`) — not only master's — was funneled through master's
  single Wi-Fi link (`worker → master eth0 → master wlan0 → NAS`), a
  real double-hop-over-Wi-Fi bottleneck that was very likely a
  contributing factor to the severe NFS slowness observed during the
  2026-08-21/22 post-reboot recovery (a plain `ls` on an NFS mount took
  ~4s at one point), on top of the SD-card and NAS-side contention
  identified at the time.

### New design (migration started 2026-08-22, see git history for status)

Flat network: every node (master, `k8s-1`, `k8s-2`, `k8s-3`) connects
directly to the same switch as a peer on `192.168.0.0/24`, no
master-mediated routing. The switch's uplink (port 1 of the GS305) goes
straight to the home router, not through master. Master's own path to
the NAS also moves from Wi-Fi to wired Ethernet, for the same latency/
reliability reason.

- **Gains:** master is no longer a SPOF for worker networking; every
  node gets a low-latency wired path to the NAS instead of funneling
  through one Wi-Fi link; direct SSH from the Mac to every node (no more
  hopping through master to reach `k8s-1`/`k8s-2`).
- **Cost:** the tower loses the "move it anywhere with Wi-Fi" property —
  it now needs a fixed location with a wired LAN drop, same as any other
  wired device. Accepted deliberately: the wired-NAS-link change alone
  already required a fixed wired location, so the portability benefit of
  the old design was moot regardless of whether the worker network was
  also flattened.
- **Port budget:** the GS305 has 5 ports. Port 1 is the router uplink,
  leaving exactly 4 for the 4 permanent nodes (master + `k8s-1` +
  `k8s-2` + `k8s-3`) — zero spare at steady state. This matters
  specifically for the master-replacement step of a rolling rebuild: the
  safe approach (build/validate the new master Pi alongside the old one
  before cutting over — see "Restoring onto replacement hardware" below)
  needs a 5th connection that doesn't exist once all three other nodes
  are already permanently plugged in. Work around it by either
  temporarily unplugging a worker for the few minutes of validation, or
  validating the new master via a direct Mac connection before the final
  unplug-old/plug-new swap into its permanent port.
- Once this migration is complete, update the "Cluster Topology" section
  of `CLAUDE.md` — it still documents the old subnet split and the
  "workers reachable from master only" SSH-hop requirement, both of
  which stop being true.

---

## Phase 0 — Provisioning a New Node (OS + first boot)

Covers getting a fresh Pi from bare SD card to "SSH-reachable with
passwordless sudo and a stable IP" — everything Phase 1 below silently
assumes already exists. Worked out live during the `k8s-3` build,
2026-08-22.

### 0a. Flash the SD card

Raspberry Pi Imager, current OS list choice: **Ubuntu Server 26.04 LTS**
(64-bit) — Server, not Desktop (headless, no GUI needed); 26.04 because
Ubuntu's April releases are always LTS (20.04, 22.04, 24.04, 26.04) and
using the newest available one maximizes runway before hitting the exact
EOL problem that started this whole rebuild (see git history/commit
messages around 2026-08-19 through 2026-08-22 for that story). Confirmed
live: ships with cgroup v2 by default (`stat -fc %T /sys/fs/cgroup/` →
`cgroup2fs`), which matters — newer k3s/kubelet hard-refuses to start on
cgroup v1, and the fleet's original 20.04 install was cgroup v1.

In recent Imager versions there's no separate gear-icon "Advanced
options" step — for Server images it goes straight from storage
selection into the customisation screen. Set:
- **Hostname**: `k8s-N` (matches existing convention — `k8s`, `k8s-1`,
  `k8s-2`, `k8s-3`, ...)
- **Username**: `ubuntu`, with a password (Imager requires one even
  though SSH will use key auth)
- **Enable SSH**: on, "Allow public-key authentication only", using the
  same public key already authorized on the existing nodes

### 0b. First boot

Boot it connected to the switch. If it doesn't show up on the network
within a few minutes and the green ACT LED shows continuous, evenly-
spaced blinking that never settles or stops — that's ambiguous (it
doesn't match the Pi 4 bootloader's actual error codes, which are
counted flash-groups with pauses between them, not continuous) — **try
a power cycle before assuming a bad flash**. This is exactly what
happened building `k8s-3`: the first boot attempt never came up on the
network at all; a power cycle immediately after fixed it with no
re-flash needed. If it still doesn't come up after a power cycle, HDMI
to any monitor (even a TV) gives a direct read on what's actually
happening — much faster than guessing from LEDs or repeated network
scans.

To find it once booted: try `ping <hostname>.local` first (mDNS/Avahi —
not guaranteed present on Ubuntu Server images, so absence doesn't mean
it's not up), and failing that, a full subnet ping sweep compared
against already-known devices:
```sh
for i in $(seq 1 254); do
  (ping -c1 -W 500 192.168.0.$i >/dev/null 2>&1 && echo "192.168.0.$i alive") &
done; wait
```
Verify any new address is actually the Pi (not a coincidentally-timed
lease from an unrelated device — this cost real time during the `k8s-3`
build, chasing what turned out to be the Ring doorbell) before doing
anything else to it: `ssh ubuntu@<ip> "hostname; stat -fc %T
/sys/fs/cgroup/"`.

### 0c. Passwordless sudo

Imager-provisioned images do **not** set up passwordless sudo — `sudo`
over a non-interactive SSH session fails with "sudo: interactive
authentication is required" (confirmed live, not just a missing-TTY
issue: `sudo -n` fails outright). This needs one interactive,
password-entering pass per new node — from your own terminal (not
something to route through an agent, since it needs the account
password you set in Imager, not the SSH key):
```sh
ssh ubuntu@<ip>
echo "ubuntu ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ubuntu-nopasswd
```
Matches how the existing three nodes are already configured. Everything
after this point (static IP, k3s install, ongoing operations) can be
done non-interactively.

### 0d. Static IP

IP scheme on the flat `192.168.0.0/24` network (see "Physical & Network
Topology" above): master is `.8`; workers get `.8N` — `k8s-1`/`k8s-2`
will move here from their old `192.168.8.x` addresses when they're
reimaged, `k8s-3` is `.83`.

Imager leaves the interface on DHCP; replace
`/etc/netplan/50-cloud-init.yaml`:
```yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses:
        - 192.168.0.8N/24
      routes:
        - to: default
          via: 192.168.0.1
      nameservers:
        addresses:
          - 192.168.0.1
```
then `sudo netplan apply`. **The SSH session you ran that from will hang
or die** — expected, since the interface's address just changed out from
under it; reconnect on the new IP in a fresh session (and expect a
"host key verification failed" / trust-on-first-use prompt for that new
IP even though it's the same host and key — `known_hosts` keys off
address, not identity).

At this point the node is ready for Phase 1's "Worker nodes" section
(or, for a master replacement, the "Restoring onto replacement
hardware" procedure below) — but that needs the rest of the cluster
reachable first if joining an existing one.

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

### Local container registry

`registry/deployment.yaml` deploys `registry:2` (NFS-backed PVC, NodePort 30500) as the
target for locally-built custom/CVE-patched images going forward, replacing the `docker
save` / `scp` / `k3s ctr images import` workflow used throughout this repo's history (see
`### Librarium local fork images` and `### ISFDB mirror` below, and every entry in
`trivy/patched-images.yaml` — all still on the old workflow as of 2026-07-27, migrating
opportunistically on each one's next rebuild rather than all at once).

Two steps here are **not** managed by Flux/GitOps and must be redone by hand on a fresh
cluster — they're node-local and workstation-local config, outside Kubernetes' object model
entirely:

**1. Containerd trust, on every node (master + both workers):**

```sh
cat <<'EOF' > /tmp/registries.yaml
mirrors:
  "127.0.0.1:30500":
    endpoint:
      - "http://127.0.0.1:30500"
EOF

# Master
scp /tmp/registries.yaml ubuntu@k8s.local:/tmp/registries.yaml
ssh ubuntu@k8s.local "sudo mkdir -p /etc/rancher/k3s && sudo cp /tmp/registries.yaml /etc/rancher/k3s/registries.yaml && sudo systemctl restart k3s"

# Workers (via master hop) — /etc/rancher/k3s/ doesn't exist by default on a fresh worker, mkdir -p first
ssh ubuntu@k8s.local "scp /tmp/registries.yaml k8s-1:/tmp/ && scp /tmp/registries.yaml k8s-2:/tmp/"
ssh ubuntu@k8s.local "ssh k8s-1 'sudo mkdir -p /etc/rancher/k3s && sudo cp /tmp/registries.yaml /etc/rancher/k3s/registries.yaml && sudo systemctl restart k3s-agent'"
ssh ubuntu@k8s.local "ssh k8s-2 'sudo mkdir -p /etc/rancher/k3s && sudo cp /tmp/registries.yaml /etc/rancher/k3s/registries.yaml && sudo systemctl restart k3s-agent'"
```

The endpoint is deliberately `127.0.0.1:30500`, not a specific node's IP — a NodePort
service is reachable via *every* node's own address including localhost, regardless of
which node the registry pod actually lands on, so the same config file is correct
unchanged on all three nodes rather than needing to know/hardcode where the pod is
scheduled.

**2. Docker Desktop trust, on the Mac (for `docker push` from the build machine):**

Add to `~/.docker/daemon.json`:
```json
"insecure-registries": ["192.168.0.8:30500"]
```
(`192.168.0.8` is the master's LAN IP / `k8s.local` — a real address, unlike the
node-local `127.0.0.1:30500` above, since the Mac isn't a cluster node.) Then either
Docker Desktop → Settings → Docker Engine → **Apply & Restart**, or quit/relaunch Docker
Desktop from the CLI — either way this restarts the whole Docker daemon, briefly stopping
*every* currently-running container on the Mac, not just anything k8s-related. Check what
else is running first (`docker ps`) and confirm before restarting; containers without a
`restart: unless-stopped`/`always` policy won't come back on their own afterward.

Both are genuinely one-time per node/machine — plain HTTP + anonymous access, deliberately
simple since this registry is never reachable outside the LAN.

**New image workflow, once both are set up:**
```sh
docker build -t 192.168.0.8:30500/<name>:<tag> .
docker push 192.168.0.8:30500/<name>:<tag>
```
Then in the manifest, reference `127.0.0.1:30500/<name>:<tag>` (matching the containerd
mirror config — not the `192.168.0.8` address used for the push, that's Mac-only) with
`imagePullPolicy: IfNotPresent`. No SSH, no per-node `ctr images import`, kubelet just
pulls it the normal way on whichever node schedules the pod.

**If `docker push` fails with a TLS/EOF error** (curl to `http://192.168.0.8:30500/v2/`
works fine, but the push tries `https://` and fails) — `~/.docker/daemon.json` having the
`insecure-registries` entry isn't enough on its own; Docker Desktop only actually applies
it after **Settings → Docker Engine → Apply & Restart** (or a full quit/relaunch), which
restarts the whole daemon and silently kills every Mac-side container that doesn't have a
`restart: unless-stopped`/`always` policy (confirmed live 2026-08-14: would have taken down
unrelated long-running dev containers with no restart policy). Rather than restart Docker
Desktop just to push one image, push via a disposable `crane` container instead — it takes
an explicit `--insecure` flag per-invocation, no daemon config needed:
```sh
docker save 192.168.0.8:30500/<name>:<tag> -o /tmp/image.tar
docker run --rm -v /tmp/image.tar:/image.tar --entrypoint sh \
  gcr.io/go-containerregistry/crane:debug \
  -c "crane push /image.tar 192.168.0.8:30500/<name>:<tag> --insecure"
```
Check `docker ps` for anything without a restart policy before ever restarting Docker
Desktop for an unrelated reason, same caution as the containerd-trust step above.

Registry storage has no automatic garbage collection — `registry:2` never deletes old
tags/layers on its own. Not a problem yet at this repo's current image count/churn, but
worth knowing before the 20Gi PVC fills up someday (`registry garbage-collect`, run inside
the pod, is the standard fix — `REGISTRY_STORAGE_DELETE_ENABLED=true` is already set to
allow this).

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

### Librarium local fork images

`librarium/api-deployment.yaml` and `librarium/web-deployment.yaml` reference **locally built
images pushed to the local registry** (`127.0.0.1:30500/librarium-{api,web}:<version>`,
`imagePullPolicy: IfNotPresent`) instead of the upstream `ghcr.io/fireball1725/*` tags. This is
temporary: it carries the ISFDB metadata provider and its generic provider-config-fields UI,
which are out as PRs against upstream but not yet merged —

- `github.com/ennui2342/librarium-api` branch `feat/isfdb-provider` — upstream PRs #45 and #46
- `github.com/ennui2342/librarium-web` branch `feat/refresh-metadata-by-title` — upstream PR #44
  (carries a cherry-pick of PR #44's work; check `~/projects/librarium/CLAUDE.md` for the current
  deployed branch before rebuilding, it drifts as PRs get rebased/superseded)

**Versioned tags, not a floating one**: earlier this used a single reused tag
(`local-isfdb`) that was never actually pushed anywhere (only `ctr images import`ed per node) —
unparseable by `trivy`'s reconcile-scanner and impossible to tell which build was actually
running. Every rebuild now stamps a fresh `1.YYYYMMDD.HHMM` tag (see global `~/.claude/CLAUDE.md`
for the convention) and pushes it to the registry; the manifest is updated to point at that exact
tag. Rebuild whenever source changes, on a cluster rebuild, or if a worker's local registry-pull
cache is somehow lost (rare — registry storage is the source of truth now, not per-node
containerd cache):

```sh
cd ~/projects/librarium/librarium-api
git checkout feat/isfdb-provider  # confirm this matches CLAUDE.md's "currently deployed" branch
go build ./... && go test ./...   # don't skip — see this repo's own CLAUDE.md

TAG="1.$(date +%Y%m%d).$(date +%H%M)"
docker build --build-arg VERSION=26.4.4-isfdb -t 192.168.0.8:30500/librarium-api:$TAG .
docker push 192.168.0.8:30500/librarium-api:$TAG
cd ..

cd ~/projects/librarium/librarium-web
git checkout feat/refresh-metadata-by-title
npm run build && npx vitest run

docker build --build-arg LIBRARIUM_VERSION=26.4.3-isfdb -t 192.168.0.8:30500/librarium-web:$TAG .
docker push 192.168.0.8:30500/librarium-web:$TAG
cd ..
```

Then update `librarium/api-deployment.yaml` and `librarium/web-deployment.yaml`'s `image:` to
`127.0.0.1:30500/librarium-{api,web}:$TAG`, commit, push, let Flux reconcile.

**Once PRs #44/#45/#46 merge upstream and ship in a tagged `fireball1725` release**, revert
`librarium/api-deployment.yaml` and `librarium/web-deployment.yaml` back to
`ghcr.io/fireball1725/librarium-{api,web}:<new-version>` with `imagePullPolicy: IfNotPresent`,
commit. No node-side cleanup needed — old registry tags just sit unused in
`registry-data` (see "Local container registry" above re: manual `registry garbage-collect`).

The ISFDB provider itself is configured, not auto-enabled: in Librarium's admin settings
(Metadata Providers), set ISFDB's **Mirror base URL** to
`http://isfdb-adapter.isfdb.svc.cluster.local:8080` and enable it.

### ISFDB mirror

`isfdb/adapter-deployment.yaml` and `isfdb/refresh-cronjob.yaml` reference a **locally built
image pushed to the local registry** (`127.0.0.1:30500/isfdb-mirror:<version>`,
`imagePullPolicy: IfNotPresent`) — same pattern as the Librarium local fork images above. Source
is the standalone public repo `github.com/ennui2342/isfdb-adapter` (a clean reference
implementation anyone can self-host — see its own `CLAUDE.md`/`README.md`), not anything embedded
in this repo. On a cluster rebuild, before the adapter/CronJob pods can schedule, clone (or reuse
an existing `~/projects/isfdb-adapter` checkout), build, and push:

```sh
cd ~/projects/isfdb-adapter   # or: git clone https://github.com/ennui2342/isfdb-adapter.git && cd isfdb-adapter
TAG="1.$(date +%Y%m%d).$(date +%H%M)"
docker build -t 192.168.0.8:30500/isfdb-mirror:$TAG .
docker push 192.168.0.8:30500/isfdb-mirror:$TAG
```

Then update `isfdb/adapter-deployment.yaml` and `isfdb/refresh-cronjob.yaml`'s `image:` to
`127.0.0.1:30500/isfdb-mirror:$TAG`, commit, push, let Flux reconcile. Every rebuild gets its own
tag (see global `~/.claude/CLAUDE.md`'s versioned-release convention) rather than reusing a
floating `local` tag — that's what previously made this image invisible to `trivy`'s
reconcile-scanner (no parseable version to compare against) and made it impossible to tell which
build was actually deployed.

Config (`MARIADB_ROOT_PASSWORD`, `ISFDB_WIKI_USERNAME`, `ISFDB_WIKI_PASSWORD`) stays as-is —
`isfdb/isfdb-secret.yaml` (SOPS-encrypted) is unaffected by where the image source lives; it's
passed into the built image as env vars by the Deployment/CronJob either way.

The MariaDB PVC is empty on a fresh cluster — trigger an initial import manually rather than
waiting for Sunday:

```sh
kubectl create job --from=cronjob/isfdb-refresh isfdb-refresh-manual -n isfdb
```

**This takes 20-25 minutes** (confirmed on a live run — was 34 minutes before `refresh.py` started
filtering the dump down to the 11 tables `adapter.py` actually queries, dropping the ~65 MediaWiki
editing/moderation tables — user accounts, edit history, view-count analytics — that make up
roughly half the dump's rows but are never read), almost entirely spent importing into NFS-backed
MariaDB (`activeDeadlineSeconds: 3600` accounts for this with headroom — don't shrink it below
~30 min, an earlier tighter budget got killed mid-import on the first live run). A failed/killed
run is harmless — the atomic swap in `refresh.py` only happens after the staging import passes a
row-count sanity check, so it just leaves the mirror empty (fresh cluster) or last week's data
(routine refresh) rather than serving partial data.

The refresh job's login to the ISFDB wiki occasionally gets a transient `403` on the very first
attempt of a session (observed during initial testing; unclear whether it's Cloudflare-side or
something about connection reuse) but succeeds on retry — `backoffLimit: 2` on the CronJob handles
this automatically, no action needed unless it fails 3 times in a row.

### opsimath

Fully automated as of 2026-08-06, same pattern as `taskmgt/` — **not** the manually-built
local-registry pattern used by Librarium/ISFDB. Source is the standalone public repo
`github.com/ennui2342/opsimath` (Rails 8.1 / Ruby 4.0 / Postgres 18); its own
`.github/workflows/build.yml` builds and pushes a real monotonic version tag
(`1.YYYYMMDD.RUNNUMBER`) to `ghcr.io/ennui2342/opsimath` on every push to `master`. Flux's own
image automation (`flux-system/opsimath-image-automation.yaml`: `ImageRepository` scans every 5m,
`ImagePolicy` picks the newest semver tag, `ImageUpdateAutomation` commits the updated tag back to
`opsimath/web-deployment.yaml`/`worker-deployment.yaml` via the `$imagepolicy` Setter markers next
to each `image:` line) picks it up and redeploys automatically — no manual build/push/redeploy
step for routine updates, `taskmgt/`'s own RUNBOOK entry doesn't exist for the same reason.

**Only needed on a from-scratch cluster rebuild, before Flux's image automation has ever run once**
(nothing to scan/update yet): manually build and push a first image so the Deployments have
something to pull —

```sh
cd ~/projects/opsimath   # or: git clone https://github.com/ennui2342/opsimath.git && cd opsimath
TAG="1.$(date +%Y%m%d).$(date +%H%M)"
docker build -t 192.168.0.8:30500/opsimath:$TAG .
docker push 192.168.0.8:30500/opsimath:$TAG
```

Then update `opsimath/web-deployment.yaml` and `opsimath/worker-deployment.yaml`'s `image:` (both
Deployments' main container plus the worker's `wait-for-schema` initContainer — three lines total,
keep the `$imagepolicy` Setter comment intact on each) to `127.0.0.1:30500/opsimath:$TAG`, commit,
push, let Flux reconcile. Once CI has pushed a real tag to GHCR and the image automation has run at
least once, this manual path shouldn't be needed again — the Setter markers mean Flux will happily
overwrite whatever tag is there, local-registry or GHCR, with the newest GHCR one on its next scan.

**`RAILS_MASTER_KEY` must come from `~/projects/opsimath/config/master.key`** (gitignored in that
repo, never committed anywhere) — it decrypts `config/credentials.yml.enc`, which holds
`secret_key_base` plus real Goodreads/Discord bot secrets. On a fresh cluster rebuild, re-derive
`opsimath/opsimath-secret.yaml`'s `RAILS_MASTER_KEY` from that same local file (read it directly
into the SOPS-encrypt step, never echo it to a terminal or intermediate file) — `APP_DATABASE_PASSWORD`
can just be freshly generated, it only needs to match what's set on the bundled Postgres instance.

**Postgres 18 gotcha, confirmed live 2026-08-05 (same one opsimath's own `docker-compose.yml`
already documents):** if the `opsimath-db` pod's *first-ever* boot gets interrupted mid-`initdb`
(pod killed/rescheduled before initialization finishes), Postgres sees a non-empty but incomplete
data directory on restart and skips re-running init — silently leaving `pg_hba.conf` without the
`host all all all scram-sha-256` line pod-to-pod connections need, so every other pod's connection
fails with `no pg_hba.conf entry for host ..., no encryption`, permanently, until the data
directory is wiped. If this happens: `kubectl delete pod opsimath-db-0 -n opsimath && kubectl
delete pvc data-opsimath-db-0 -n opsimath` (safe pre-data; the StatefulSet recreates both) and let
it initialize fresh, uninterrupted this time — check `kubectl exec -n opsimath opsimath-db-0 --
cat /var/lib/postgresql/18/docker/pg_hba.conf` afterward for that line before assuming it's fixed.

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

## Master Datastore Backup & Restore

**Not GitOps-managed** — same category as containerd trust config and Docker Desktop registry
trust above: node-local host setup outside k8s's own object model, must be redone by hand on a
fresh cluster (see "Adding this on a fresh master" below).

This cluster runs the k3s default SQLite/kine datastore (not embedded etcd) on the master, with
no control-plane HA — a single master is a real single point of failure. Deliberately **not**
solved with a 3-node etcd-quorum HA control plane (considered and rejected 2026-08-19: needs an
odd number >= 3 dedicated server nodes to actually help — 2 is worse than 1, not better — and
dedicating 2 Raspberry Pis to sit mostly idle for quorum insurance was judged a bad trade for a
homelab, especially since a real control-plane outage that day — a failed k3s upgrade crash-loop —
had zero workload impact: pods kept serving the whole time, only `kubectl`/Flux access paused).
Instead: cheap daily snapshots to the NAS plus a documented restore procedure onto spare
hardware, trading instant failover for a bounded (minutes, not seconds) recovery window.

### What gets backed up

`/usr/local/bin/k3s-backup.sh` on the master (source of truth: `master-backup/k3s-backup.sh` in
this repo — copy it there, it's not deployed via GitOps, same pattern as `k8s-toolbox/Dockerfile`),
cron'd daily at 03:30 (ubuntu's own crontab, not
root's — relies on the passwordless sudo already configured for that user), logs to
`/home/ubuntu/k3s-backup.log`:

1. **`state.db`** — a consistent, WAL-safe online snapshot via `sqlite3 .backup` (the official
   SQLite backup API, not a raw file copy — safe to run against the live, actively-written
   database without stopping k3s or risking a torn snapshot mid-checkpoint).
2. **`tls/`, `cred/`, `token`** — the cluster's CA certs, all component TLS material, kubeconfigs,
   and join token. These change rarely (only on cert rotation), so a plain copy is fine — no
   live-consistency concern the way the active database has. This is what lets a restored master
   keep its *exact* cluster identity, so existing workers can reconnect without re-joining.

Packaged as `k3s-master-backup-<timestamp>.tar.gz` and written to
`/mnt/k8s/k3s-master-backups/` — the same NAS (`nas.local:/mnt/md0/k8s`) that backs every PVC in
this cluster, already mounted on the master at `/mnt/k8s`. 14-day retention, pruned automatically
each run. Each archive is ~17MB.

**Contains real cluster credentials in plaintext** (private keys, admin kubeconfigs, the join
token) — same trust boundary as everything else on this NAS share (LAN-only, never exposed
beyond it), not separately encrypted. Don't casually cat/display archive contents.

On failure, posts to the `monitoring` Discord webhook (fetched via `kubectl get secret
discord-webhook` — the script runs on the bare host, not as a pod, so it can't resolve
`tasks.k8s.ecafe.org` the way in-cluster CronJobs do; Discord's public HTTPS endpoint works fine
from anywhere with internet access, so that's the only alert channel here, not also a `tm` task
the way health-monitor/pvc-usage-monitor do it). On success, it's silent — check
`/home/ubuntu/k3s-backup.log` or list `/mnt/k8s/k3s-master-backups/` directly to confirm it's
still running if you want to verify without waiting for a failure.

### Restoring onto replacement hardware

For when the master's SD card dies and you're swapping in the spare Pi kept in storage for
exactly this:

```sh
# 1. Fresh Ubuntu install on the spare Pi/SD card, same hostname (k8s / k8s.local) and static
#    IP (192.168.0.8) as the original master — workers and every *.k8s.ecafe.org DNS entry
#    assume this identity, not just "some node is the master".

# 2. Install k3s SERVER but do not let it auto-init a new empty cluster - stop it immediately
#    after the binary/service files are laid down, before it creates a fresh empty datastore:
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=<current version, check tm tasks 325e53da etc. for what's live> sh -
sudo systemctl stop k3s

# 3. Pick the most recent archive from /mnt/k8s/k3s-master-backups/ (mount the NAS export first
#    if this is genuinely fresh hardware: see Phase 2 above) and restore it over the freshly
#    created (but not yet real) datastore:
sudo rm -rf /var/lib/rancher/k3s/server/db /var/lib/rancher/k3s/server/tls /var/lib/rancher/k3s/server/cred /var/lib/rancher/k3s/server/token
sudo mkdir -p /var/lib/rancher/k3s/server/db
sudo tar -xzf /mnt/k8s/k3s-master-backups/k3s-master-backup-<latest>.tar.gz -C /tmp/restore
sudo mv /tmp/restore/state.db /var/lib/rancher/k3s/server/db/state.db
sudo mv /tmp/restore/tls /var/lib/rancher/k3s/server/tls
sudo mv /tmp/restore/cred /var/lib/rancher/k3s/server/cred
sudo mv /tmp/restore/token /var/lib/rancher/k3s/server/token
sudo chown -R root:root /var/lib/rancher/k3s/server

# 4. Start k3s and verify:
sudo systemctl start k3s
sudo journalctl -u k3s -f   # watch for a clean start, not a crash-loop
kubectl get nodes           # workers should reconnect on their own - same CA/token as before,
                             # no re-join needed
kubectl get pods -A         # spot-check nothing's missing
flux get kustomizations     # confirm GitOps reconciliation resumes cleanly
```

**Data loss window:** anything that changed between the last successful daily snapshot and the
failure is gone — for this cluster, that's mostly Flux-reconciled state (which self-heals from
git on the next reconcile anyway) and any manually-applied changes since the last backup, not
application data (that lives in PVCs on the NAS, backed up independently and unaffected by this
procedure entirely).

**This has not been rehearsed against real failed hardware** — the mechanics above are correct
per k3s's own documented datastore layout and were verified by restoring a backup archive's
`state.db` locally (`sqlite3 ... PRAGMA integrity_check` — passed), but a full end-to-end restore
onto genuinely fresh hardware hasn't been drilled. Worth doing once, deliberately, when the spare
Pi arrives — better to find gaps in a planned test than during a real outage.

### Adding this on a fresh master (cluster rebuild)

After Phase 3's Flux bootstrap, `scp master-backup/k3s-backup.sh` from this repo to
`/usr/local/bin/k3s-backup.sh` on the new master, `chmod +x`, and re-add the cron line — nothing
here survives a from-scratch rebuild automatically, it's pure host-local state like the
containerd trust config above.

---

## CVE Patch Management

The `monitoring/cve-scanner` CronJob (Monday 07:00, `trivy/trivy.yaml`) scans the live cluster
weekly with Trivy and files a `tm` task per vulnerable image, tagged `+cli.claude-code.k8s
<cli.cve-scanner`. It dedupes on creation (one task per image, updated in place if the CVE set
changes, auto-closed if the image is no longer flagged) and skips filing tasks entirely for
images already tracked in `trivy/patched-images.yaml` (see below).

A separate aswarm pipeline, `agent-orchestrator` (`/Volumes/SSD/pipelines/agent-orchestrator.yaml`,
renamed 2026-08-19 from `nightly-agents`, then again same day from `k8s-orchestrator` once it was
clear the pipeline itself is general-purpose task routing, not k8s-specific — its only live wiring
today just happens to be this repo — runs every 30min on the Mac now, not just 1am/6am, though
CVE/health work still only actually dispatches during the 1am/6am window; see that file's
description and `agent-orchestrator-prompt.md` Step 1.5 for the per-specialist eligibility
mechanics), works this queue one task at a time: the orchestrator prompt
(`~/projects/agents/k8s/agent-orchestrator-prompt.md` — renamed 2026-08-19 from
`nightly-orchestrator-prompt.md`, then `orchestrator-prompt.md`) selects the highest-priority
eligible task and routes it to the upgrade specialist (`~/projects/agents/k8s/upgrade-prompt.md` —
a separate, tracked git repo, not part of this one; there was previously also an untracked mirror
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
