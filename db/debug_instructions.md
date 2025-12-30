
```sh
kubectl logs api-56fb7964f9-q58tt -n series-api-ns

# ...
# wait-for-it.sh: timeout occurred after waiting 30 seconds for db:5432
# ...
```

Get the DB endpoint:
```sh
aws rds describe-db-instances \
  --query "DBInstances[*].Endpoint.Address" \
  --output text

# but since we know the DB instance identifier:
aws rds describe-db-instances \
  --db-instance-identifier $DB_NAME \
  --query "DBInstances[0].Endpoint.Address" \
  --output text

```

Run this from inside your cluster (tests raw network connectivity):

```sh
kubectl run -it --rm debug --image=busybox -n series-api-ns -- sh

```


Inside the pod, check:

```sh
nslookup <your-rds-endpoint>

```

```sh
telnet <your-rds-endpoint> 5432

## telnet: can't connect to remote host (192.168.66.82): Connection timed out
```

❌ The pod cannot reach RDS: Connection timed out

This means:
🔥 Your RDS security group is NOT allowing inbound traffic from your EKS worker node security group.


```sh
# Get the RDS security group
aws rds describe-db-instances \
  --db-instance-identifier $DB_NAME \
  --query "DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId" \
  --output text

# Get worker node security group from EC2
aws ec2 describe-instances \
  --filters "Name=tag:eks:nodegroup-name,Values=$NODEGROUP_NAME" \
            "Name=tag:eks:cluster-name,Values=$CLUSTER_NAME" \
  --query "Reservations[*].Instances[*].SecurityGroups[*].GroupId" \
  --output text



# Authorize the ingress
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG \
  --protocol tcp \
  --port 5432 \
  --source-group $EKS_NODE_SG

# {
#     "Return": true,
# ...
# }
```


Perfect ✅ — the ingress rule was successfully created.

What this means:

RDS security group (sg-039dba25a2db22b8e) now allows TCP port 5432 from your EKS worker node security group (sg-0a5654346f791227f)

Your EKS pods can now reach the RDS instance


```sh
telnet series-db.cqmq0u1myitv.us-east-1.rds.amazonaws.com 5432


Connected to series-db...
Escape character is '^]'.

```

Restart the API pod:
```sh
kubectl rollout restart deployment api -n series-api-ns

```



```sh
aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE_IDENTIFIER \
  --query "DBInstances[0].DBSubnetGroup.Subnets[].SubnetIdentifier"


aws eks describe-nodegroup \
  --cluster-name $CLUSTER_NAME \
  --nodegroup-name $NODEGROUP_NAME \
  --query "nodegroup.subnets"


kubectl -n $CLUSTER_NS run net-debug \
  -it --rm \
  --image=ghcr.io/nicolaka/netshoot \
  -- bash



aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --query "cluster.resourcesVpcConfig.clusterSecurityGroupId"

# node sg
aws ec2 describe-instances \
  --filters "Name=tag:eks:cluster-name,Values=$CLUSTER_NAME" \
  --query "Reservations[].Instances[].SecurityGroups[].GroupId" \
  --output text


aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE_IDENTIFIER \
  --query "DBInstances[0].VpcSecurityGroups"

aws ec2 describe-security-groups \
  --group-ids sg-04c84e2cdcc3f1543 \
  --query "SecurityGroups[0].IpPermissions"





```