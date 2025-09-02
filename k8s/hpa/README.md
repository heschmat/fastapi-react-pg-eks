
# HPA + CA

## Horizontal Pod Autoscaler (HPA)

What it does: Scales pods (replicas of a Deployment/ReplicaSet/StatefulSet) up or down based on metrics like CPU, memory, or custom metrics.

Scope: Inside the cluster. It assumes nodes already exist and just adjusts workloads.

Example:
- Your web app deployment runs 3 pods.
- CPU usage goes above 80%.
- HPA scales to 6 pods (provided the cluster has capacity).


## Cluster Autoscaler (CA)

What it does: Scales nodes in the cluster up or down depending on whether workloads can be scheduled.

Scope: Cluster-level. Talks directly to the cloud provider (EKS → AWS Auto Scaling Groups / Managed Node Groups).

Example:
- Your HPA scales a deployment to 6 pods.
- 2 of them can't be scheduled due to lack of resources.
- CA requests AWS to add more EC2 nodes.

NOTE: to setup CA refer to `./helm/cluster-autoscaler/README.md`

## Setup HPA 
```sh
kubectl top nodes
kubectl top pods

kubectl logs -n kube-system deploy/metrics-server

kubectl -n kube-system edit deploy metrics-server


# if it doesn't work, install `metrics-server`
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

```


Our HPA is bound to Deployment/cpu-demo. 
```sh

# deploy a CPU-intensive app
kubectl apply -f cpu-demo-full.yaml

# attach an hpa (this HPA scales between 1 and 10 replicas if CPU > 50%)
kubectl apply -f hpa.yaml

k get hpa -w
```

### cpu: <unknown>/50% issue
If you get
```sh
$ k get hpa
NAME           REFERENCE             TARGETS              MINPODS   MAXPODS   REPLICAS   AGE
cpu-demo-hpa   Deployment/cpu-demo   cpu: <unknown>/50%   1         10        1          52m
```
one reason could be that the `metrics-server` cannot scrape kubelet metrics:

```sh
$ kubectl logs -n kube-system deploy/metrics-server
Found 2 pods, using pod/metrics-server-75c7985757-7788r
I0902 00:33:39.399905       1 serving.go:380] Generated self-signed cert (/tmp/apiserver.crt, /tmp/apiserver.key)
...
E0902 00:35:39.891855       1 scraper.go:149] "Failed to scrape node" err="Get \"https://192.168.17.53:10250/metrics/resource\": dial tcp 192.168.17.53:10250: connect: connection refused" node="ip-192-168-17-53.ec2.internal"
E0902 00:36:04.899307       1 scraper.go:147] "Failed to scrape node, timeout to access kubelet" err="Get \"https://192.168.17.53:10250/metrics/resource\": context deadline exceeded" node="ip-192-168-17-53.ec2.internal" timeout="10s"
```
By default, kubelets expose metrics on port 10250, secured with TLS. `metrics-server` in EKS needs the `--kubelet-insecure-tls` flag, otherwise it refuses the kubelet's self-signed cert.

Edit the deployment and add the flag:

```sh
$ kubectl -n kube-system edit deploy metrics-server

# make sure the following flags are there:
args:
  - --secure-port=10251
  - --cert-dir=/tmp
  - --kubelet-insecure-tls
  - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
  - --kubelet-use-node-status-port
  - --metric-resolution=15s

```

# verify APIservice # available 
```sh
$ kubectl get apiservice v1beta1.metrics.k8s.io
NAME                     SERVICE                      AVAILABLE   AGE
v1beta1.metrics.k8s.io   kube-system/metrics-server   True        61m
```




If all went ok, you should see an output similar to this:
```yaml
$ k get hpa -w
NAME           REFERENCE             TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
cpu-demo-hpa   Deployment/cpu-demo   cpu: 0%/50%   1         10        10         38m
cpu-demo-hpa   Deployment/cpu-demo   cpu: <unknown>/50%   1         10        1          39m
cpu-demo-hpa   Deployment/cpu-demo   cpu: 242%/50%        1         10        1          39m
cpu-demo-hpa   Deployment/cpu-demo   cpu: 2%/50%          1         10        4          39m
cpu-demo-hpa   Deployment/cpu-demo   cpu: 159%/50%        1         10        5          40m
cpu-demo-hpa   Deployment/cpu-demo   cpu: 130%/50%        1         10        10         40m
cpu-demo-hpa   Deployment/cpu-demo   cpu: 0%/50%          1         10        10         40m
cpu-demo-hpa   Deployment/cpu-demo   cpu: 30%/50%         1         10        10         41m
cpu-demo-hpa   Deployment/cpu-demo   cpu: 76%/50%         1         10        10         41m
cpu-demo-hpa   Deployment/cpu-demo   cpu: 93%/50%         1         10        10         42m
cpu-demo-hpa   Deployment/cpu-demo   cpu: 92%/50%         1         10        10         42m
cpu-demo-hpa   Deployment/cpu-demo   cpu: 15%/50%         1         10        10         42m
cpu-demo-hpa   Deployment/cpu-demo   cpu: 0%/50%          1         10        10         42m
cpu-demo-hpa   Deployment/cpu-demo   cpu: 0%/50%          1         10        10         47m
cpu-demo-hpa   Deployment/cpu-demo   cpu: 0%/50%          1         10        3          47m
cpu-demo-hpa   Deployment/cpu-demo   cpu: 0%/50%          1         10        1          47m
```



## Test
Each request → triggers stress -c 1 -t 10s → CPU usage spikes → HPA scales pods → CA adds nodes if needed.
```sh
kubectl port-forward svc/cpu-demo 8080:8080


# in another terminal hit
curl http://localhost:8080
# that tells the hammer sidecar to run: `subprocess.Popen(["stress-ng", "--cpu", "1", "--timeout", "10s"])`
# which generate CPU load inside the pod

```
## ddx:
```sh
# in case the sidecar fails, check its log:
kubectl logs deploy/cpu-demo -c hammer

```



Alternatively to generate the load, apply the `load-generator-job`:
```sh
k apply -f load-generator-job.yaml
```

🔥 the flow that we'll is like so: (numbers are arbitrar)

- At first, HPA showed cpu: <unknown>/50% → no metrics.
- After the load generator started curling /start, the pod began running stress-ng.
- HPA metrics updated: cpu: 251%/50%.
- The deployment scaled from 1 → 4 → 6 → 10 replicas in seconds.
- Now it's stabilizing around 120–160%/50% with 10 replicas (your max).
- If the newly scheduled pods are pending, then CA launches a new node, if possible.

So our HPA + metrics-server + stress test + CA pipeline is fully working ✅


## observe scaling
In a separate terminal, watch things happen:
```sh
# you should see CPU usage rising and replicas increasing
kubectl get hpa -w

kubectl get deploy cpu-demo -w
kubectl get pods -l app=cpu-demo -w


# check ca logs
# when the cluster runs out of room, new pods will go Pending, and CA should scale up nodes.
kubectl -n kube-system logs -f deployment/cluster-autoscaler

```
