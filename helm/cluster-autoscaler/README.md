
# CA

When we deploy Cluster Autoscaler, it is just a Kubernetes pod running on one of your worker nodes in EKS. So, from Kubernetes' perspective, it's a "normal" pod like any other.
For a pod to interact with AWS APIs (like creating or terminating EC2 instances), it needs AWS credentials. There are two common ways this happens:

## 1) Directly from the Node IAM Role

Each EC2 node in an EKS cluster has an instance role attached. Any process running on that node can use the node's IAM role to make AWS API calls.

If we don't configure anything special, the Cluster Autoscaler pod will just use the node's role by default. The caveat is that this way all pods on that node can use the same permissions — not least privilege.

The is how you do it:
```sh
export ASG_NAME=$(eksctl get nodegroup --cluster "$CLUSTER_NAME" --name "$NODEGROUP_NAME" -o json | jq -r '.[0].AutoScalingGroupName')
echo $ASG_NAME

# We must tag the ASG so Cluster Autoscaler can discover and manage it:

aws autoscaling create-or-update-tags --tags "ResourceId=${ASG_NAME},ResourceType=auto-scaling-group,Key=eks:cluster-autoscaler/enabled,Value=true,PropagateAtLaunch=true"
aws autoscaling create-or-update-tags --tags "ResourceId=${ASG_NAME},ResourceType=auto-scaling-group,Key=eks:cluster-autoscaler/${CLUSTER_NAME},Value=owned,PropagateAtLaunch=true"


NODE_ROLE_ARN=$(aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$NODEGROUP_NAME" --query "nodegroup.nodeRole" --output text)
NODE_ROLE_NAME=$(basename $NODE_ROLE_ARN)
echo $NODE_ROLE_ARN
echo $NODE_ROLE_NAME

# attach the required policy
aws iam attach-role-policy --role-name $NODE_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AutoScalingFullAccess
```

```sh
# deploy
kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/cluster-autoscaler-1.32.0/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml


# the manifest we just applied is a generic one, hence we now need to customize the deployment: 
kubectl -n kube-system edit deployment cluster-autoscaler


# incorporate these: 

# 1) command:
## 1a) look for the command: section and update it
- --cluster-name=<our-cluster-name>

## 1b)  also add these two useful flags:
- --balance-similar-node-groups
- --skip-nodes-with-system-pods=false

- --scale-down-unneeded-time=2m
- --scale-down-delay-after-add=1m

# 2) annotations
# add this annotation to the pod template to prevent it from being evicted:
      annotations:
        cluster-autoscaler.kubernetes.io/safe-to-evict: "false"
```

# verify
```sh
kubectl -n kube-system get pods -l app=cluster-autoscaler
```

## 2) Via IRSA (IAM Roles for Service Accounts)

IRSA is a mechanism where we attach a dedicated IAM role to a Kubernetes Service Account.

The Cluster Autoscaler pod uses that service account, so it gets only the permissions attached to that IAM role. This avoids giving all pods on the node the same wide permissions.


```sh
# OIDC (OpenID Connect) allows pods to authenticate to AWS using service accounts (IRSA).
eksctl utils associate-iam-oidc-provider \
  --cluster $CLUSTER_NAME \
  --region $AWS_REGION \
  --approve

cd helm/cluster-autoscaler/
aws iam create-policy \
  --policy-name AmazonEKSClusterAutoscalerPolicy \
  --policy-document file://cluster-autoscaler-policy.json

# create & link a SA to the IAM role with the proper policy (AmazonEKSClusterAutoscalerPolicy) via IRSA
eksctl create iamserviceaccount \
  --name cluster-autoscaler \
  --namespace kube-system \
  --cluster $CLUSTER_NAME \
  --attach-policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/AmazonEKSClusterAutoscalerPolicy \
  --approve \
  --override-existing-serviceaccounts

```
This does 3 things:
- Creates (or updates) the cluster-autoscaler ServiceAccount in kube-system
- Creates an IAM role with the policy above
- Annotates the ServiceAccount with the IAM role ARN

Now the CA pod can assume this IAM role. You can check the IAM role associated in SA description, `annotation` section:
```sh
# e.g.,
ubuntu:cluster-autoscaler$ kubectl describe sa cluster-autoscaler -n kube-system
Name:                cluster-autoscaler
Namespace:           kube-system
Labels:              app.kubernetes.io/managed-by=eksctl
Annotations:         eks.amazonaws.com/role-arn: arn:aws:iam::137423019814:role/eksctl-series-api-addon-iamserviceaccount-kub-Role1-NHXWJ2fbsSOh
Image pull secrets:  <none>
Mountable secrets:   <none>
Tokens:              <none>
Events:              <none>

```

Next:

```sh
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo update


cd ./helm/cluster-autoscaler/

helm install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  -f values.yaml


# verify:
k get pods -n kube-system | grep autoscaler
```

```yaml
                  ┌──────────────────────────────┐
                  │        Kubernetes Pod        │
                  │   (cluster-autoscaler)       │
                  └──────────────┬───────────────┘
                                 │
                                 │ uses
                                 │
                  ┌──────────────▼───────────────┐
                  │ Kubernetes Service Account   │
                  │  (cluster-autoscaler in      │
                  │   kube-system namespace)     │
                  └──────────────┬───────────────┘
                                 │ mapped via IRSA
                                 │
                  ┌──────────────▼───────────────┐
                  │ IAM Role for Service Account │
                  │ (bound by OIDC trust policy) │
                  │   + AmazonEKSCluster...Policy│
                  └──────────────┬───────────────┘
                                 │
                                 │ temporary creds
                                 │
                  ┌──────────────▼───────────────┐
                  │         AWS APIs             │
                  │ (AutoScaling, EC2, IAM, etc.)│
                  └──────────────┬───────────────┘
                                 │
                                 │ updates desired
                                 │ capacity
                                 │
      ┌──────────────────────────▼──────────────────────────┐
      │            EC2 Auto Scaling Group (ASG)             │
      │ (eks-series-api-ng-1acc82a6-...-335976f2c189)       │
      └──────────────────────────┬──────────────────────────┘
                                 │
                                 │ launches/terminates
                                 │ EC2 nodes
                                 │
                  ┌──────────────▼───────────────┐
                  │      EKS Worker Nodes        │
                  │ (join cluster, run pods)     │
                  └──────────────────────────────┘


```

### ddx:
```sh
kubectl get sa cluster-autoscaler -n kube-system

kubectl get sa cluster-autoscaler -n kube-system -o yaml | grep eks.amazonaws.com/role-arn


aws autoscaling describe-auto-scaling-groups \
  --region us-east-1 \
  --query "AutoScalingGroups[].Tags[?Key=='k8s.io/cluster-autoscaler/series-api' || Key=='k8s.io/cluster-autoscaler/enabled']" \
  --output table
``

## Test

```sh
kubectl create deployment stress --image=busybox -- /bin/sh -c "while true; do sleep 30; done"
kubectl scale deployment stress --replicas=10

```
We should see sth like this for some of the pods:
```sh
$ k describe pod stress-6f6974ffdb-wr5kr | grep Event -A 20
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  26s   default-scheduler  0/1 nodes are available: 1 Too many pods. preemption: 0/1 nodes are available: 1 No preemption victims found for incoming pod.

# in the node's description logs we should see that `allocatable` pods and `non-terminated` pods are equal.
# i.e., there's no room left for more pods to be deployed to this node.
k describe node <node-name> # get the node name from: k get nodes

```

👉 REMEMBER: when Cluster Autoscaler runs, whether it uses node IAM role or IRSA role, it always uses temporary STS credentials under the hood

# How IAM normally works

When we attach an IAM role to an EC2 instance (or a Kubernetes pod via IRSA), AWS does NOT give it long-lived access keys.

Instead, it gives a short-lived security token (temporary credentials) via the AWS Security Token Service (STS). These credentials usually last for 1 hour (can be shorter/longer depending on configuration) and are automatically rotated.

## With node IAM role
If a pod just uses the node's IAM role, the EC2 metadata service provides temporary STS credentials for that role.

** N.B. Every process on that node can fetch them. **

## With IRSA (IAM Roles for Service Accounts)

The pod presents a signed service account token to AWS STS via the OIDC provider. AWS STS verifies the token, then issues temporary credentials scoped to the IAM role linked to that service account.

Again, these expire and get refreshed automatically by the SDK.


```sh
# cd helm/cluster-autoscaler
kubectl apply -f debug-pod.yaml

# exec into the pod
kubectl exec -it debug -n kube-system -- bash


# inside the pod install AWS CLI
yum install -y awscli

# check which role it's using
aws sts get-caller-identity

```

Sample output:
```yaml
bash-4.2# aws sts get-caller-identity
{
    "Account": "873716023878", 
    "UserId": "AROA4W3MIQJDJS34DB5RV:botocore-session-1756733891", 
    "Arn": "arn:aws:sts::873716023878:assumed-role/eksctl-series-api-addon-iamserviceaccount-kub-Role1-sGBAou4WoVrO/botocore-session-1756733891"
}

```


🔎 Key details

`Arn → assumed-role/eksctl-series-api-addon-iamserviceaccount-kub-Role1-sGBAou4WoVrO/...`

That's the IAM role eksctl created when you ran eksctl create iamserviceaccount. It's the role linked to the cluster-autoscaler service account in kube-system.

`botocore-session-...` is the temporary STS session name issued when the AWS SDK requested credentials.

The AWS SDK (in the pod) automatically calls `STS AssumeRoleWithWebIdentity` using the service account token.

STS issues temporary credentials (default ~1 hour lifetime). Each time it refreshes, a new session is created → so the `botocore-session-<random>` string will change. i.e., every rotation, there is a new session name, but always tied to the same role.

This confirms these are **ephemeral STS creds**, not permanent keys.

`Account = 873716023878` is the AWS account ID.

`UserId` in `aws sts get-caller-identity` just means *who you are in this session*, not a permanent IAM user.
