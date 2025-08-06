#!/bin/bash

set -e

# Prompt for necessary information
read -p "Enter AWS region: " AWS_REGION
read -p "Enter AWS Account ID: " AWS_ACC_ID
read -p "Enter ECR repository name (e.g. fastapi-app): " ECR_REPO_NAME
read -p "Enter Docker project folder (e.g. backend): " PROJECT_FOLDER
read -p "Enter Docker image tag (e.g. v1): " IMG_TAG
read -p "Enter Kubernetes manifest filename (e.g. api.yaml): " K8S_MANIFEST

# Check if ECR repo exists
if aws ecr describe-repositories --repository-names "$ECR_REPO_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "❌ ECR repository '$ECR_REPO_NAME' already exists. Aborting."
  exit 1
fi

# Create the ECR repo
echo "✅ Creating ECR repository..."
output=$(aws ecr create-repository --repository-name "$ECR_REPO_NAME" --region "$AWS_REGION")
repo_uri=$(echo "$output" | jq -r '.repository.repositoryUri')
echo "📦 Repository URI: $repo_uri"

# Authenticate Docker with ECR
echo "🔐 Authenticating Docker with ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
docker login --username AWS --password-stdin "$AWS_ACC_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

# Build Docker image
echo "🔨 Building Docker image..."
docker build -t "$ECR_REPO_NAME" "$PROJECT_FOLDER"

# Tag and push Docker image
echo "🚀 Tagging and pushing Docker image to ECR..."
docker tag "$ECR_REPO_NAME:latest" "${repo_uri}:${IMG_TAG}"
docker push "${repo_uri}:${IMG_TAG}"
docker rmi "$ECR_REPO_NAME:latest"

# Update the image in the Kubernetes manifest
K8S_MANIFEST_PATH="k8s/manifests/$K8S_MANIFEST"
if [[ ! -f "$K8S_MANIFEST_PATH" ]]; then
  echo "❌ Kubernetes manifest '$K8S_MANIFEST_PATH' not found. Aborting."
  exit 1
fi

echo "🛠 Updating image in Kubernetes manifest..."
sed -i.bak \
  "s|image:.*|image: $AWS_ACC_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO_NAME:$IMG_TAG|" \
  "$K8S_MANIFEST_PATH"

echo "📄 Updated manifest:"
grep image: "$K8S_MANIFEST_PATH"
