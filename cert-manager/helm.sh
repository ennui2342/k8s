# https://hashbang.nl/blog/manage-ssl-certificates-and-ingress-for-services-in-k3s-kubernetes-cluster-using-cert-manager-letsencrypt-and-traefik
# https://cert-manager.io/docs/installation/helm/

helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.8 \
  --set installCRDs=true
