# Deploying Amazon RDS PostgreSQL for an EKS Cluster

This guide explains how to deploy a **PostgreSQL RDS instance** inside the same VPC as your **Amazon EKS cluster**, configure networking/security groups, and connect it to your Kubernetes workloads.

---

## 📋 Prerequisites

* An existing **EKS cluster** (`$CLUSTER_NAME`) running in AWS.
* **AWS CLI** configured (`aws configure`).
* **kubectl** installed and connected to your EKS cluster.
* Environment variables set for DB configuration:

```bash
# we assume the followings are set.
export CLUSTER_NAME=series-api
export AWS_REGION=us-east-1
export CLUSTER_NS=series-api-ns

export POSTGRES_DB=ratings_db
export POSTGRES_USER=postgres
export POSTGRES_PASSWORD=SuperSecretPassword!
```

---

## 1. Get the EKS VPC ID

```bash
VPC_ID=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)

echo $VPC_ID
```

---

## 2. Identify Subnets

List all subnets in the VPC:

```bash
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[*].{ID:SubnetId,AZ:AvailabilityZone,MapPublicIpOnLaunch:MapPublicIpOnLaunch}" \
  --output table
```

Filter private subnets (where `MapPublicIpOnLaunch=false`):

```bash
PRIVATE_SUBNETS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[?MapPublicIpOnLaunch==\`false\`].SubnetId" \
  --output text)

echo $PRIVATE_SUBNETS
```

---

## 3. Security Groups

Create a **new SG for RDS**:

```bash
DB_SG_ID=$(aws ec2 create-security-group \
  --group-name "${POSTGRES_DB}-sg" \
  --description "Security group for RDS Postgres in series-api" \
  --vpc-id "$VPC_ID" \
  --region "$AWS_REGION" \
  --query 'GroupId' \
  --output text)

echo "Created RDS SG: $DB_SG_ID"
```

Get the **security group** of the first EKS node:
```bash
NODE_SG_ID=$(aws ec2 describe-instances \
  --filters "Name=private-dns-name,Values=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')" \
  --query "Reservations[].Instances[].SecurityGroups[].GroupId" \
  --output text)
echo $NODE_SG_ID
```

Allow PostgreSQL (port 5432) traffic from EKS nodes:

```bash
aws ec2 authorize-security-group-ingress \
  --group-id $DB_SG_ID \
  --protocol tcp \
  --port 5432 \
  --source-group $NODE_SG_ID \
  --region $AWS_REGION
```

---

## 4. Create an RDS Subnet Group

```bash
aws rds create-db-subnet-group \
  --db-subnet-group-name $DB_SUBNET_GRP_NAME \
  --db-subnet-group-description "Private subnets for RDS Postgres in series-api" \
  --subnet-ids $PRIVATE_SUBNETS \
  --region $AWS_REGION
```

*(Optional: delete later)*
If it fails, delete and re-create it again.
```bash
aws rds delete-db-subnet-group \
  --db-subnet-group-name $DB_SUBNET_GRP_NAME \
  --region $AWS_REGION
```

---

## 5. Launch the RDS Instance

```bash
# DB_INSTANCE_IDENTIFIER: name shown on AWS console; also part of the DB ENDPOINT
aws rds create-db-instance \
  --db-instance-identifier $DB_INSTANCE_IDENTIFIER \
  --db-name $POSTGRES_DB \
  --engine postgres \
  --engine-version 17 \
  --db-instance-class db.t3.micro \
  --allocated-storage 20 \
  --master-username $POSTGRES_USER \
  --master-user-password $POSTGRES_PASSWORD \
  --vpc-security-group-ids $DB_SG_ID \
  --db-subnet-group-name $DB_SUBNET_GRP_NAME \
  --backup-retention-period 7 \
  --multi-az \
  --no-publicly-accessible \
  --region $AWS_REGION
```

Wait until the DB is available. This will take about 15 minutes.

```bash
aws rds wait db-instance-available \
  --db-instance-identifier $DB_INSTANCE_IDENTIFIER \
  --region $AWS_REGION
```

---

## 6. Retrieve RDS Endpoint

```bash
DB_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE_IDENTIFIER \
  --region $AWS_REGION \
  --query "DBInstances[0].Endpoint.Address" \
  --output text)

echo "RDS endpoint: $DB_ENDPOINT"
```

---

## 7. Store Database Credentials in Kubernetes Secrets

```bash
kubectl -n $CLUSTER_NS create secret generic postgres-secret \
  --from-literal=POSTGRES_USER=$POSTGRES_USER \
  --from-literal=POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
  --from-literal=POSTGRES_DB=$POSTGRES_DB \
  --from-literal=POSTGRES_HOST=$DB_ENDPOINT \
  --from-literal=POSTGRES_PORT=5432 \
  --from-literal=DATABASE_URL=postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$DB_ENDPOINT:5432/$POSTGRES_DB
```

---

## 8. Test Connection from Kubernetes

Run a debug pod with PostgreSQL client:

```bash
kubectl -n $CLUSTER_NS run -i --tty test-db --rm \
  --image=postgres:17 \
  --env="host=$DB_ENDPOINT" \
  --env="db_user=$POSTGRES_USER" \
  --env="db_name=$POSTGRES_DB" \
  -- bash
```

Inside the pod:

```bash
psql -h $host -U $db_user -d $db_name -p 5432
# You'll be prompted to give your db password.
```

Example output:

```sql
ratings_db=> \dt
              List of relations
 Schema |      Name       | Type  |  Owner   
--------+-----------------+-------+----------
 public | alembic_version | table | postgres
 public | ratings         | table | postgres
(2 rows)

ratings_db=> select * from ratings;
 id | username | series_name | rating
----+----------+-------------+--------
  1 | Kimi     | Friends     |      3
  2 | Kimi     | Dark        |      4
(2 rows)
```

---

## ✅ Summary

You now have:

* A **PostgreSQL RDS instance** deployed in your EKS VPC.
* A **dedicated security group** allowing only EKS worker nodes to connect.
* Credentials securely stored in **Kubernetes secrets**.
* Verified database connectivity inside the cluster.

---

## 🧹 Cleanup (Optional)

To delete resources:

```bash
# Takes about 7 minutes.
aws rds delete-db-instance \
  --db-instance-identifier $DB_INSTANCE_IDENTIFIER \
  --skip-final-snapshot \
  --region $AWS_REGION

aws rds wait db-instance-deleted \
  --db-instance-identifier $DB_INSTANCE_IDENTIFIER \
  --region $AWS_REGION

aws rds delete-db-subnet-group \
  --db-subnet-group-name $DB_SUBNET_GRP_NAME \
  --region $AWS_REGION

aws ec2 delete-security-group \
  --group-id $DB_SG_ID \
  --region $AWS_REGION
```

---
