
# CA

When we deploy Cluster Autoscaler, it is just a Kubernetes pod running on one of your worker nodes in EKS. So, from Kubernetes' perspective, it's a "normal" pod like any other.
For a pod to interact with AWS APIs (like creating or terminating EC2 instances), it needs AWS credentials. There are two common ways this happens:

There are two common ways this happens:

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

kubectl -n kube-system get pods -l app=cluster-autoscaler


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
  --attach-policy-arn arn:aws:iam::$AWS_ACC_ID:policy/AmazonEKSClusterAutoscalerPolicy \
  --approve \
  --override-existing-serviceaccounts

```
This does 3 things:
- Creates (or updates) the cluster-autoscaler ServiceAccount in kube-system
- Creates an IAM role with the policy above
- Annotates the ServiceAccount with the IAM role ARN

Now the CA pod can assume this IAM role.

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
kubectl get sa cluster-autoscaler -n kube-system

kubectl get sa cluster-autoscaler -n kube-system -o yaml | grep eks.amazonaws.com/role-arn


aws autoscaling describe-auto-scaling-groups \
  --region us-east-1 \
  --query "AutoScalingGroups[].Tags[?Key=='k8s.io/cluster-autoscaler/series-api' || Key=='k8s.io/cluster-autoscaler/enabled']" \
  --output table


## Test

```sh
kubectl create deployment stress --image=busybox -- /bin/sh -c "while true; do sleep 30; done"
kubectl scale deployment stress --replicas=10

```
