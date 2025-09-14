$ cat k8s/eks-cluster-manage.sh
#!/bin/bash

set -euo pipefail

# Load environment variables from root .env file
ROOT_DIR="$(dirname "$(dirname "$0")")"
ENV_FILE="$ROOT_DIR/.env"

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1091
  source "$ENV_FILE"
else
  echo "Warning: .env file not found at '$ENV_FILE', environment variables must be set manually."
fi

usage() {
  cat <<EOF
Usage: $0 {create|delete} [options]

Required environment variables:
  CLUSTER_NAME   - EKS cluster name
  AWS_REGION     - AWS region
  INSTANCE_TYPE  - EC2 instance type for node group
  NODEGROUP_NAME - Node group name

Options (override env vars):
  --min N         Minimum number of nodes (default: 1)
  --desired N     Desired number of nodes (default: 1)
  --max N         Maximum number of nodes (default: 4)
  --spot true|false   Use spot instances (default: true)

Optional environment variables:
  CLUSTER_NS - Default namespace for kubectl
EOF
  exit 1
}

if [ $# -lt 1 ]; then
  usage
fi

ACTION=$1
shift

# Defaults (can be overridden by env or CLI)
MIN_SIZE="${MIN_SIZE:-1}"
DESIRED_CAPACITY="${DESIRED_CAPACITY:-1}"
MAX_SIZE="${MAX_SIZE:-4}"
SPOT="${SPOT:-true}"

# Parse CLI options
while [[ $# -gt 0 ]]; do
  case "$1" in
    --min)
      MIN_SIZE="$2"
      shift 2
      ;;
    --desired)
      DESIRED_CAPACITY="$2"
      shift 2
      ;;
    --max)
      MAX_SIZE="$2"
      shift 2
      ;;
    --spot)
      SPOT="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

# Validate required environment variables
required_vars=(CLUSTER_NAME AWS_REGION INSTANCE_TYPE NODEGROUP_NAME)
for var in "${required_vars[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "Error: Please set the environment variable '$var'."
    exit 1
  fi
done

# Validate SPOT
if [[ "$SPOT" != "true" && "$SPOT" != "false" ]]; then
  echo "Error: SPOT must be 'true' or 'false'. Got '$SPOT'."
  exit 1
fi

# Template file located in the same directory as this script
SCRIPT_DIR="$(dirname "$0")"
TEMPLATE_FILE="$SCRIPT_DIR/cluster-config-template.yaml"

if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "Error: Template file '$TEMPLATE_FILE' not found."
  exit 1
fi

# Generate temporary config file with values filled in
CONFIG_FILE=$(mktemp)

sed \
  -e "s/{{CLUSTER_NAME}}/$CLUSTER_NAME/g" \
  -e "s/{{REGION}}/$AWS_REGION/g" \
  -e "s/{{INSTANCE_TYPE}}/$INSTANCE_TYPE/g" \
  -e "s/{{NODEGROUP_NAME}}/$NODEGROUP_NAME/g" \
  -e "s/{{MIN_SIZE}}/$MIN_SIZE/g" \
  -e "s/{{DESIRED_CAPACITY}}/$DESIRED_CAPACITY/g" \
  -e "s/{{MAX_SIZE}}/$MAX_SIZE/g" \
  -e "s/{{SPOT}}/$SPOT/g" \
  "$TEMPLATE_FILE" > "$CONFIG_FILE"

# Run eksctl command
case "$ACTION" in
  create)
    echo "Creating cluster '$CLUSTER_NAME' in region '$AWS_REGION'..."
    eksctl create cluster -f "$CONFIG_FILE"

    echo "Updating kubeconfig..."
    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"

    if [ -n "${CLUSTER_NS:-}" ]; then
      echo "Setting default namespace to '$CLUSTER_NS'..."
      if ! kubectl get namespace "$CLUSTER_NS" >/dev/null 2>&1; then
        kubectl create namespace "$CLUSTER_NS"
      else
        echo "Namespace '$CLUSTER_NS' already exists."
      fi

      kubectl config set-context --current --namespace="$CLUSTER_NS"
    fi
    ;;
  delete)
    echo "Deleting cluster '$CLUSTER_NAME' in region '$AWS_REGION'..."
    eksctl delete cluster --name "$CLUSTER_NAME" --region "$AWS_REGION"
    ;;
  *)
    usage
    ;;
esac

# Clean up temp config
rm -f "$CONFIG_FILE"
echo "Done."
