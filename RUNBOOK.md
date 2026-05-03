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

---

## Phase 5 — Post-Bootstrap Checks

### Grafana admin password

The admin credentials are in `grafana/grafana-admin-secret.yaml` (SOPS-encrypted),
applied automatically by Flux. On a clean rebuild Grafana reads the password from
the `GF_SECURITY_ADMIN_PASSWORD` env var on first start — no manual steps needed.

### Grafana dashboards and datasources

Dashboards and the InfluxDB datasource are provisioned declaratively via
ConfigMaps (`grafana-dashboards` and `grafana-datasources`). They come up
automatically with the pod — no manual import needed.

Dashboard JSON sources live in `grafana/dashboard-*.json`. To update a
dashboard: edit in the UI, re-export via the API, overwrite the file, and commit:

```sh
curl -s -u "admin:$PASS" http://grafana.k8s.ecafe.org/api/dashboards/uid/<uid> \
  | python3 -c "import json,sys; d=json.load(sys.stdin); d['dashboard']['version']=0; print(json.dumps({'dashboard':d['dashboard'],'overwrite':True},indent=2))" \
  > grafana/dashboard-<name>.json
```

Then regenerate the ConfigMap and commit:

```sh
cd /Volumes/SSD/sync/projects/k8s
python3 - << 'EOF'
import json, yaml
dashboards = {
    "nas-monitor.json":    "dashboard-nas-monitor.json",
    "observatory.json":    "dashboard-98rU06mRk.json",
    "solar.json":          "dashboard-1-GoRoH4z.json",
    "weather-station.json":"dashboard-orrdjQlnk.json",
}
cm = {"apiVersion":"v1","kind":"ConfigMap","metadata":{"name":"grafana-dashboards","namespace":"monitoring"},"data":{}}
for dest, src in dashboards.items():
    d = json.load(open(f"grafana/{src}"))
    inner = d["dashboard"]; inner["version"] = 0
    cm["data"][dest] = json.dumps(inner, indent=2)
yaml.dump(cm, open("grafana/grafana-dashboards.yaml","w"), default_flow_style=False, allow_unicode=True)
EOF
git add grafana/ && git commit -m "Update Grafana dashboards"
```

### Tailscale

The operator is deployed via `tailscale/helmrelease.yaml`. OAuth credentials
are read from the SOPS-encrypted `operator-oauth` secret via `valuesFrom` —
no manual steps needed. After the operator pod comes up, approve any new
Tailscale devices in the admin console if they are new machine keys.

### SyncThing

SyncThing config is persisted on NFS (`/mnt/md0/sync/config`), so device
identity and folder config survive a cluster rebuild without any extra steps.
Verify the pod is up and the web UI is reachable at `syncthing.k8s.ecafe.org`.

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
