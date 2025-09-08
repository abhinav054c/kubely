
#!/bin/bash

DEPLOY_SCRIPT="./service.sh"

# Default values
CONFIG_FILE="cluster.config"
# AWS configuration
AWS_REGION="ap-south-1"
VPC_ID="vpc-06b196c8efd6b20b7"
NAMESPACE_NAME="callmatic"
DRY_RUN="false"
AWS_ACCOUNT_ID=""

# Parse params
while [[ $# -gt 0 ]]; do
  case $1 in
    --config-file)
      CONFIG_FILE="$2"
      shift 2
      ;;
    --aws-region)
      AWS_REGION="$2"
      shift 2
      ;;
    --vpc-id)
      VPC_ID="$2"
      shift 2
      ;;
    --namepace)
      NAMESPACE_NAME="$2"
      shift 2
      ;;
    --account-id)
      AWS_ACCOUNT_ID="$2"
      shift 2
      ;;
    --dry-run)
      if [[ -n "$2" && "$2" != --* ]]; then
        DRY_RUN="$2"
        shift 2
      else
        DRY_RUN="true"
        shift 1
      fi
      ;;
    --*) # catch unknown options
      echo "❌ Unknown option: $1"
      exit 1
      ;;
    *) # no more options
      break
      ;;
  esac
done


if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: Config file $CONFIG_FILE not found"
  exit 1
fi



ECR_SECRET_NAME="ecr-pull-secret"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "Creating Kubernetes namespace: ${NAMESPACE_NAME}..."
kubectl create namespace "${NAMESPACE_NAME}" --dry-run=client -o yaml | kubectl apply -f -
echo "Namespace created or already exists."
echo "Fetching ECR authentication token..."
ECR_PASSWORD=$(aws ecr get-login-password --region "${AWS_REGION}")
echo "Creating or updating Kubernetes Docker registry secret: ${ECR_SECRET_NAME}..."
kubectl create secret docker-registry "${ECR_SECRET_NAME}" \
  --namespace="${NAMESPACE_NAME}" \
  --docker-server="${ECR_REGISTRY}" \
  --docker-username=AWS \
  --docker-password="${ECR_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secret created or updated."

# Strip usage/help block between ###

awk '
  BEGIN {start_usage_block=0; end_usage_block=0; skipheader=0; skipped_header=0;}
  /^###/ {
    if(!start_usage_block&&!end_usage_block){
        start_usage_block=!start_usage_block
        next
    }
    if(start_usage_block&&!end_usage_block){
        end_usage_block=!end_usage_block
        next
    }
  }
  {
    if(end_usage_block){
        if(!skipheader){
            skipheader = !skipheader
            next
        }
    }
    if(skipheader){
        if(!skipped_header){
            skipped_header = !skipped_header
            next
        }
    }
    if(skipped_header){
        print
    }
  }

# ' "$CONFIG_FILE" | while read -r line; do
  # Skip empty lines
  [[ -z "$line" ]] && continue

  echo "$line"
  # Parse quoted values safely into positional parameters
  eval set -- $line

  name=$1 
  service=$2 
  cpu_requests=$3 
  cpu_limits=$4 
  mem_requests=$5 
  mem_limits=$6 
  pod_requests=$7 
  pod_limits=$8 
  envs=$9
  serviceport="${10}" 
  exposeport="${11}" 
  public_gateway="${12}" 
  allowed_ips="${13}" 
  cmd="${14}" 
  gitrepo="${15}" 
  branch="${16}" 
  commit="${17}"


  echo "Deploying service: $name"
  echo "name: $name"
  echo " service: $service"
  echo " cpu_requests: $cpu_requests"
  echo " cpu_limits: $cpu_limits"
  echo " mem_requests: $mem_requests"
  echo " mem_limits: $mem_limits"
  echo " pod_requests: $pod_requests"
  echo " pod_limits: $pod_limits"
  echo " envs: $envs"
  echo " targetPort: $serviceport"
  echo " port: $exposeport"
  echo " public gateway: $public_gateway"
  echo " allowed_ips: $allowed_ips"
  echo " cmd: $cmd"
  echo " gitrepo: $gitrepo"
  echo " branch: $branch"
  echo " commit: $commit"
  echo " "
  "$DEPLOY_SCRIPT" "$name" "$service" "$cpu_requests" "$cpu_limits" "$mem_requests" "$mem_limits" "$pod_requests" "$pod_limits" "$envs" "$serviceport" "$exposeport" "$public_gateway" "$allowed_ips" "$cmd" "$gitrepo" "$branch" "$commit" "$ACCOUNT_ID" "$AWS_REGION" "$NAMESPACE_NAME" "$ECR_SECRET_NAME" "$VPC_ID" "$DRY_RUN"
done


