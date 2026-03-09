helm repo add tailscale https://pkgs.tailscale.com/helmcharts
helm install tailscale-operator tailscale/tailscale-operator \
     --namespace tailscale \
     --set oauth.clientId=$(kubectl get secret tailscale-operator -n tailscale -o jsonpath='{.data.client-id}' | base64 -d) \
     --set oauth.clientSecret=$(kubectl get secret tailscale-operator -n tailscale -o jsonpath='{.data.client-secret}' | base64 -d) \
     --wai
