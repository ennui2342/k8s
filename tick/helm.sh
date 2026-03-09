helm repo add influxdata https://helm.influxdata.com/
helm install --namespace=monitoring -f influxdb-values.yaml influxdb influxdata/influxdb
helm -n monitoring install -f telegraf-values.yaml telegraf influxdata/telegraf
