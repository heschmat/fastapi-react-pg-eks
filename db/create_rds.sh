#!/usr/bin/env bash
set -euo pipefail

### REQUIRED ENV VARS
REQUIRED_VARS=(
  CLUSTER_NAME
  AWS_REGION
  CLUSTER_NS
  POSTGRES_DB
  POSTGRES_USER
  POSTGRES_PASSWORD
  DB_NAME
  DB_SUBNET_GRP_NAME
  POSTGRES_VERSION
  DB_STORAGE_GB
  DB_INSTANCE_CLASS
)

for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "❌ Environment variable '$var' is required but not set."
    exit 1
  fi
done

echo "✅ All required environment variables are set."

echo "🔍 Fetching VPC ID from EKS cluster..."
VPC_ID=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)

echo "➡️ VPC ID: $VPC_ID"


echo "🔍 Fetching private subnet IDs..."
PRIVATE_SUBNETS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[?MapPublicIpOnLaunch==\`false\`].SubnetId" \
  --output text)

echo "➡️ Private subnets: $PRIVATE_SUBNETS"


echo "🔍 Fetching EKS worker node security group..."
NODE_SG_ID=$(aws ec2 describe-instances \
  --filters "Name=private-dns-name,Values=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')" \
  --query "Reservations[].Instances[].SecurityGroups[].GroupId" \
  --output text)

echo "➡️ Node security group: $NODE_SG_ID"


echo "🔧 Creating security group for RDS..."
DB_SG_ID=$(aws ec2 create-security-group \
  --group-name "${DB_NAME}-sg" \
  --description "Security group for RDS Postgres in $CLUSTER_NAME" \
  --vpc-id "$VPC_ID" \
  --region "$AWS_REGION" \
  --query 'GroupId' \
  --output text)

echo "➡️ RDS SG created: $DB_SG_ID"


echo "🔐 Allowing traffic from EKS nodes to RDS..."
aws ec2 authorize-security-group-ingress \
  --group-id $DB_SG_ID \
  --protocol tcp \
  --port 5432 \
  --source-group $NODE_SG_ID \
  --region $AWS_REGION

echo "📦 Creating DB Subnet Group..."
aws rds create-db-subnet-group \
  --db-subnet-group-name $DB_SUBNET_GRP_NAME \
  --db-subnet-group-description "Private subnets for RDS Postgres" \
  --subnet-ids $PRIVATE_SUBNETS \
  --region $AWS_REGION

echo "🗄️ Creating RDS instance..."

aws rds create-db-instance \
  --db-instance-identifier $DB_NAME \
  --db-name $POSTGRES_DB \
  --engine postgres \
  --engine-version "$POSTGRES_VERSION" \
  --db-instance-class "$DB_INSTANCE_CLASS" \
  --allocated-storage "$DB_STORAGE_GB" \
  --master-username "$POSTGRES_USER" \
  --master-user-password "$POSTGRES_PASSWORD" \
  --vpc-security-group-ids "$DB_SG_ID" \
  --db-subnet-group-name "$DB_SUBNET_GRP_NAME" \
  --backup-retention-period 7 \
  --multi-az \
  --no-publicly-accessible \
  --region "$AWS_REGION"

echo "⏳ Waiting for DB instance to become available..."
aws rds wait db-instance-available \
  --db-instance-identifier "$DB_NAME" \
  --region "$AWS_REGION"

DB_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_NAME" \
  --region "$AWS_REGION" \
  --query "DBInstances[0].Endpoint.Address" \
  --output text)

echo "🎉 RDS endpoint: $DB_ENDPOINT"
