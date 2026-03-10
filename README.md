# k8s Homelab Fleet

GitOps source of truth for the homelab Kubernetes cluster. Flux reconciles the cluster against this repo automatically.

See [CLAUDE.md](CLAUDE.md) for full topology, service inventory, and notes for AI-assisted management.

---

## Recovery Runbook

Step-by-step guide to rebuilding the cluster from scratch. Complete each phase in order.

### Prerequisites (on the Mac)

```bash
brew install kubectl helm flux gh
# Ensure gh is authenticated: gh auth login
# Copy kubeconfig from master after k3s install:
scp ubuntu@k8s.local:~/.kube/config ~/.kube/config
```

### Phase 1 — Helm Repos

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm repo add influxdata https://helm.influxdata.com/
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add tailscale https://pkgs.tailscale.com/helmcharts
helm repo update
```

### Phase 2 — NFS Storage Provisioner

Must be up before any PVC-backed services can start.

```bash
kubectl apply -f nfs/template.yaml
# Wait for provisioner pod to be Running
kubectl wait --for=condition=Available deployment/nfs-subdir-external-provisioner --timeout=60s
```

### Phase 3 — cert-manager

Must be installed before Flux bootstrap so the ClusterIssuer CRD exists when Flux applies `cert-manager/letsencrypt-prod.yaml`.

```bash
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.8 \
  --set installCRDs=true \
  --wait
```

### Phase 4 — Monitoring Stack (InfluxDB + Telegraf + Grafana)

These are Helm-managed and not fully reconciled by Flux (Flux only manages the PV/ingress). Install them before Flux bootstrap so the PVCs bind correctly.

```bash
kubectl create namespace monitoring

# Persistent volumes (Flux will also manage these, applying here first is idempotent)
kubectl apply -f tick/pv.yaml
kubectl apply -f grafana/pv.yaml

# InfluxDB + Telegraf
helm install influxdb influxdata/influxdb \
  --namespace monitoring \
  -f tick/influxdb-values.yaml \
  --wait

helm install telegraf influxdata/telegraf \
  --namespace monitoring \
  -f tick/telegraf-values.yaml \
  --wait

# Grafana (grafana-values.yaml references existingClaim: grafana-data-pvc)
helm install grafana grafana/grafana \
  --namespace monitoring \
  -f grafana/grafana-values.yaml \
  --wait

# To retrieve the Grafana admin password:
kubectl get secret --namespace monitoring grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode; echo
```

### Phase 5 — Tailscale Operator

```bash
kubectl create namespace tailscale

# Create the OAuth secret (replace ### with real values from Tailscale admin console)
kubectl create secret generic operator-oauth \
  --namespace tailscale \
  --from-literal=client_id=### \
  --from-literal=client_secret=###

helm install tailscale-operator tailscale/tailscale-operator \
  --namespace tailscale \
  --set oauth.clientId=$(kubectl get secret operator-oauth -n tailscale -o jsonpath='{.data.client_id}' | base64 -d) \
  --set oauth.clientSecret=$(kubectl get secret operator-oauth -n tailscale -o jsonpath='{.data.client_secret}' | base64 -d) \
  --wait
```

### Phase 6 — Flux Bootstrap

Bootstraps Flux and begins reconciling all remaining services (mosquitto, home-assistant, ring-mqtt, solar/modpoll, website, taskmgt, cert-manager ClusterIssuer, etc.).

```bash
GITHUB_TOKEN=$(gh auth token) flux bootstrap github \
  --owner=ennui2342 \
  --repository=k8s \
  --branch=main \
  --path=. \
  --personal \
  --components-extra=image-reflector-controller,image-automation-controller

# Watch reconciliation
flux get all -n flux-system --watch
```

### Phase 7 — Out-of-git Secrets

These secrets are not in the repo and must be created after Flux is running.

```bash
# Discord webhook for Flux deployment notifications
kubectl create secret generic discord-webhook \
  --namespace flux-system \
  --from-literal=address=https://discord.com/api/webhooks/...
```

The `cert-manager` TLS certificate for `epigone.ecafe.org` is automatically re-issued by cert-manager once the ClusterIssuer and Certificate CR are applied by Flux — no manual step needed.

### Phase 8 — Verify

```bash
# All pods healthy
kubectl get pods -A

# Flux reconciling cleanly
flux get all -n flux-system

# Image automation scanning GHCR
kubectl get imagerepository,imagepolicy,imageupdateautomation -n flux-system

# Check a specific service
kubectl get all -n taskmgt
kubectl get all -n home-assistant
```

---

## Day-to-day Operations

**Check Flux status:**
```bash
flux get all -n flux-system
```

**Force immediate reconciliation:**
```bash
flux reconcile source git flux-system
flux reconcile kustomization flux-system
```

**Add a new service:** create a directory with manifests + `kustomization.yaml`, add the directory to the root `kustomization.yaml`, commit and push.

**Update a running service:** edit the manifest, commit and push — Flux reconciles within 10 minutes, or force it with the commands above.

**Grafana admin password:**
```bash
kubectl get secret --namespace monitoring grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode; echo
```
