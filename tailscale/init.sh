kubectl create namespace tailscale
kubectl create secret generic operator-oauth --namespace=tailscale --from-literal=client_id=### --from-literal=client_secret=### --dry-run=client -o yaml |kubectl apply -f -
