kubectl get -n monitoring secret grafana -o jsonpath="{.data.admin-password}"|base64 --decode; echo
