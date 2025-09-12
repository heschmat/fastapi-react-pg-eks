# Project Setup Guide

This guide explains how to run the application locally and how to deploy it on **Amazon EKS**.

---

## 🚀 Run the App Locally

### 1. Configure Environment Variables

```sh
cp dotenv .env
source .env
```

### 2. Build & Start Services

```sh
docker compose up --build
```

### 3. Inspect the Database

Check if the DB container is running:

```sh
docker ps --filter "name=db"
```

Connect to the database:

```sh
docker exec -it <db-container-id> psql -U $POSTGRES_USER -d $POSTGRES_DB
```

Inside `psql`:

```sql
\dt
select * from ratings limit 3;
\q
```

---

## ☸️ Run the App on EKS

### 1. Create the EKS Cluster

This repo includes a Bash script that wraps `eksctl` for creating and deleting clusters.

It uses a YAML template (`cluster-config-template.yaml`) from the same directory.

```sh
./k8s/eks-cluster-manage.sh create
```

What the script does:

* Runs `eksctl create cluster -f <config>`
* Updates kubeconfig via `aws eks update-kubeconfig`
* If `CLUSTER_NS` is provided: creates the namespace & sets it as default

---

### 2. Deploy the Cluster Autoscaler

#### Option 1: `kubectl apply` + manual patch

```sh
kubectl apply -f <your-manifest.yaml>

# Edit deployment if needed
kubectl -n kube-system edit deployment cluster-autoscaler

# Ensure correct service account is set
kubectl -n kube-system patch deployment cluster-autoscaler \
  -p '{"spec": {"template": {"spec": {"serviceAccountName": "cluster-autoscaler"}}}}'
```

#### Option 2: Helm Chart (recommended)

```sh
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo update

cd ./helm/cluster-autoscaler/

helm install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  -f values.yaml
```

---

### 3. Configure IAM Permissions

The Cluster Autoscaler needs AWS API permissions.

#### Option 1: IRSA (recommended)

```sh
aws iam create-policy \
  --policy-name ClusterAutoscalerPolicy \
  --policy-document file://cluster-autoscaler-policy.json

eksctl create iamserviceaccount \
  --cluster series-api \
  --namespace kube-system \
  --name cluster-autoscaler \
  --attach-policy-arn arn:aws:iam::$AWS_ACC_ID:policy/ClusterAutoscalerPolicy \
  --approve \
  --override-existing-serviceaccounts
```

#### Option 2: Node IAM Role

Each EKS worker node has an instance role. The Cluster Autoscaler pod can use this role to make AWS API calls, but this grants broader access than IRSA.


### 3. HPA

An HPA is always attached to a workload, usually a `Deployment` (but it can also target a `ReplicaSet` or `StatefulSet`).



So the flow is:
- Deployment defines your app and a desired replica count.
- HPA monitors metrics (CPU, memory, or custom) and adjusts that replica count up/down.
- Cluster Autoscaler (if needed) adds/removes nodes to accommodate those replicas.
