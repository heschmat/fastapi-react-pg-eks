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

## ☸️ Deploy the App on EKS

### 1. Create the EKS Cluster

This repo includes a Bash script that wraps `eksctl` for creating and deleting clusters more easily.

It uses a YAML template (`cluster-config-template.yaml`) from the same directory.

```sh
# first load the environmental variables
# a sample is provided in the file `dotenv`
source .env
./k8s/eks-cluster-manage.sh create
```

Alternatively you can pass the following parameters via cli as well:
```sh
./k8s/eks-cluster-manage.sh create --min 1 --desired 1 --max 5 --spot true
```

What the script does:

* Runs `eksctl create cluster -f <config>`
* Updates kubeconfig via `aws eks update-kubeconfig`
* If `CLUSTER_NS` is provided: creates the namespace & sets it as default


Verify that the app namespace, saved in the environmental variable `CLUSTER_NS`, is the default one, so we don't have to pass all the time.
```sh
kubectl config view --minify --output 'jsonpath={..namespace}'
## series-api-ns

```

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
# reads the env. variables mentioned in `values.yaml.template` and saves it as `values.yaml`
envsubst < values.yaml.template > values.yaml

helm install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  -f values.yaml

rm values.yaml
```

Verify
```sh
$ k get deploy -n kube-system
NAME                                        READY   UP-TO-DATE   AVAILABLE   AGE
cluster-autoscaler-aws-cluster-autoscaler   0/1     0            0           39s
```

Note: At this stage, the Cluster Autoscaler will fail to scale your cluster because it lacks the necessary AWS API permissions.

By default, pods inherit the IAM permissions of the node they're running on. While this allows them to make AWS API calls, it violates the separation of concerns principle — every pod on that node ends up with the same broad permissions, even if they don't need them.

The recommended solution is to use IAM Roles for Service Accounts (IRSA), which provides fine-grained, pod-level permissions instead of relying on the node's IAM role. The following section explains how to configure IRSA for the Cluster Autoscaler.

---

#### 3. Configure IAM Permissions

The Cluster Autoscaler needs AWS API permissions.

##### Option 1: IRSA (recommended)

```sh
aws iam create-policy \
  --policy-name ClusterAutoscalerPolicy \
  --policy-document file://cluster-autoscaler-policy.json

eksctl create iamserviceaccount \
  --cluster $CLUSTER_NAME \
  --namespace kube-system \
  --name cluster-autoscaler \
  --attach-policy-arn arn:aws:iam::$AWS_ACC_ID:policy/ClusterAutoscalerPolicy \
  --approve \
  --override-existing-serviceaccounts
```

##### Option 2: Node IAM Role

Each EKS worker node has an instance role. The Cluster Autoscaler pod can use this role to make AWS API calls, but this grants broader access than IRSA.


### 3. ECR

Make sure you can authenticate with the ECR:
```sh
# Authenticate Docker to ECR
aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS --password-stdin $AWS_ACC_ID.dkr.ecr.$AWS_REGION.amazonaws.com
```

Use the script `deploy_to_ecr.sh` to provision the ECR repository and create, tag & push the docker image for frontend and backend/api to ECR.

```sh
$ ./deploy_to_ecr.sh 
Enter AWS region: us-east-1
Enter AWS Account ID: 619472109028
Enter ECR repository name (e.g. fastapi-app): series-api
Enter Docker project folder (e.g. backend): backend
Enter Docker image tag (e.g. v1): 1.0
Enter Kubernetes manifest filename (e.g. api.yaml): api.yaml
```

### 4. Deploy the API to EKS

First generate the `secret` for the database.
```sh
# the env variables are set in .env
kubectl -n $CLUSTER_NS create secret generic postgres-secret \
  --from-literal=POSTGRES_USER=$POSTGRES_USER \
  --from-literal=POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
  --from-literal=POSTGRES_DB=$POSTGRES_DB \
  --from-literal=DATABASE_URL=$DATABASE_URL

# $ k get secret -n $CLUSTER_NS
# NAME              TYPE     DATA   AGE
# postgres-secret   Opaque   4      8s
```
Now apply the manifest files

```sh
cd k8s/manifests/
kubectl apply -f gp3-storageclass.yaml
kubectl apply -f pg-statefulset-svc.yaml
kubectl apply -f api.yaml
kubectl apply -f frontend.yaml
```

Let's test if the app is deployed correctly. For that we temporarily make the api service a `NodePort`
```sh
kubectl patch svc api -p '{"spec": {"type": "NodePort"}}'
```

Now we can send the request to the backend api:
```sh
NODE_EXT_IP=54.226.124.144
API_NODEPORT=30324

curl -X POST http:/${NODE_EXT_IP}:${API_NODEPORT}/rate \
  -H "Content-Type: application/json" \
  -d '{"username":"Kimi","series_name":"Dark","rating":4}'

```

This won't work for two reasons.
1- We need to open the inbound rule for the `API_NODEPORT`
2- More importantly, Kubernetes delegates volume creation to the **AWS EBS CSI driver** (`ebs.csi.aws.com`), but the driver hasn't yet provisioned the volume.

```sh
$ k describe pvc data-postgres-0 | kdes
Events:
  Type    Reason                Age                   From                         Message
  ----    ------                ----                  ----                         -------
  Normal  WaitForFirstConsumer  13m                   persistentvolume-controller  waiting for first consumer to be created before binding
  Normal  ExternalProvisioning  2m48s (x42 over 13m)  persistentvolume-controller  Waiting for a volume to be created either by the external provisioner 'ebs.csi.aws.com' or manually by the system administrator. If volume creation is delayed, please verify that the provisioner is running and correctly registered.
```

#### install AWS EBS CSI driver
```sh
# IAM Open ID Connect provider:
eksctl utils associate-iam-oidc-provider --region $AWS_REGION --cluster $CLUSTER_NAME --approve


eksctl create iamserviceaccount \
  --region $AWS_REGION \
  --cluster $CLUSTER_NAME \
  --namespace kube-system \
  --name ebs-csi-controller-sa \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve

# eksctl create addon --name aws-ebs-csi-driver --cluster $CLUSTER_NAME --region $AWS_REGION --service-account-role-arn arn:aws:iam::$AWS_ACC_ID:role/AmazonEKS_EBS_CSI_DriverRole
# eksctl delete addon --name aws-ebs-csi-driver --cluster $CLUSTER_NAME --region $AWS_REGION

helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update

helm upgrade --install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
  --namespace kube-system \
  --set controller.serviceAccount.create=false \
  --set controller.serviceAccount.name=ebs-csi-controller-sa

#k get pod -n kube-system | grep csi

# $ k get csidriver
# NAME              ATTACHREQUIRED   PODINFOONMOUNT   STORAGECAPACITY   TOKENREQUESTS   REQUIRESREPUBLISH   MODES        AGE
# ebs.csi.aws.com   true             false            false             <unset>         false               Persistent   12s
```

We can verify that a volume is provisioned:

```sh
aws ec2 describe-volumes \
  --filters Name=tag:kubernetes.io/created-for/pvc/name,Values=data-postgres-0 \
  --region $AWS_REGION
```

Finally we should be able to send a request to the backend api:
```sh
curl -X POST http:/${NODE_EXT_IP}:${API_NODEPORT}/rate \
  -H "Content-Type: application/json" \
  -d '{"username":"Kimi","series_name":"Dark","rating":4}'
##{"status":"success","data":{"username":"Kimi","series_name":"Dark","rating":4}}
```

### 5. ALB controller

create service account with IAM role
```sh
# AWS provides a ready-made IAM policy JSON (iam_policy.json) with all required permissions (ELB, Target Groups, Security Groups, etc.).
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.11.0/docs/install/iam_policy.json

# Create IAM Policy
aws iam create-policy \
  --policy-name AWSLBControllerIAMPolicy \
  --policy-document file://iam_policy.json

# Remove the policy document:
rm iam_policy.json

# Use eksctl to bind the above policy to a Kubernetes service account:
IAM_SA_NAME=aws-lb-ctl

eksctl create iamserviceaccount \
  --cluster $CLUSTER_NAME \
  --namespace kube-system \
  --name $IAM_SA_NAME \
  --role-name AWSEKSLBControllerRole \
  --attach-policy-arn arn:aws:iam::$AWS_ACC_ID:policy/AWSLBControllerIAMPolicy \
  --approve

```

Deploy AWS LoadBalancer Controller:
```sh
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks

VPC_ID=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)

echo $VPC_ID

# Deploy the AWS Load Balancer Controller
helm install aws-lb-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=$IAM_SA_NAME \
  --set region=$AWS_REGION \
  --set vpcId=$VPC_ID

```

verify the alb controller installation:
```sh
$ kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
NAME                                                              READY   STATUS    RESTARTS   AGE
aws-lb-controller-aws-load-balancer-controller-6dc7cb4b7b-79hjb   1/1     Running   0          39s
aws-lb-controller-aws-load-balancer-controller-6dc7cb4b7b-szjvl   1/1     Running   0          39s


# verify the correct sa is attached to the alb controller:
$ kubectl get deploy aws-lb-controller-aws-load-balancer-controller -n kube-system -o yaml | grep serviceAccountName
## serviceAccountName: aws-lb-ctl
```


deploy ingress

```sh
k apply -f k8s/manifests/ingress.yaml

aws elbv2 describe-load-balancers --region $AWS_REGION

k get ing


# make sure frontend can reach the api

$ kubectl exec -it frontend-78445f6755-9sblk -- curl -s http://api:8000/api/recent
{"detail":"Not Found"}
```


### ?. HPA

An HPA is always attached to a workload, usually a `Deployment` (but it can also target a `ReplicaSet` or `StatefulSet`).

So the flow is:
- Deployment defines your app and a desired replica count.
- HPA monitors metrics (CPU, memory, or custom) and adjusts that replica count up/down.
- Cluster Autoscaler (if needed) adds/removes nodes to accommodate those replicas.

```sh
#@TOD

```
