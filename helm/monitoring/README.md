# Observability

## Metrics & Monitoring

Install Prometheus + Grafana

```sh
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

```

Also add the config for alertmanager (the file.)
```sh
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f ./custom-kube-prometheus-stack.yml

# 
# Prometheus Operator can take up to 2 minutes reconcile.
k apply -f api/api-servicemonitor.yaml

k get servicemonitor backend -n monitoring -o yaml

```


### access the stack

1) for dev

```sh
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80

# in case you're using an ec2 instance add `--address 0.0.0.0` to the end
# and don't forget to open port 3000
# access grafana <EC2-Public-IP>:3000

# password to the Grafana UI:
# username: admin
kubectl get secret -n monitoring monitoring-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d


kubectl port-forward -n monitoring svc/prometheus-operated 9090

```


Test `/metrics` api:
```sh
kubectl run tmp-shell \
  -n series-api-ns \
  --rm -it \
  --image=curlimages/curl \
  --restart=Never -- sh

# inside the shell run:
curl http://api:8000/metrics
# 👉 If this works, your app is exposing metrics correctly.

```

```sh

kubectl get servicemonitor -n monitoring
kubectl get svc -n series-api-ns --show-labels

```
