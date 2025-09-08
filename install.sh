
#!/bin/bash

DEPLOY_SCRIPT="./service.sh"

# Default values
CONFIG_FILE="cluster.config"
# AWS configuration
AWS_REGION="ap-south-1"
VPC_ID="vpc-06b196c8efd6b20b7"
NAMESPACE_NAME="${NAMESPACE_NAME}"
DRY_RUN="false"

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

# Echo params
echo "Name: $name"
echo "Service: $service"
echo "Port: $port"
echo "Public Gateway: $public_gateway"
echo "Debug: $debug"


if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: Config file $CONFIG_FILE not found"
  exit 1
fi



ECR_SECRET_NAME="ecr-pull-secret"

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

' "$CONFIG_FILE" | while read -r line; do
  # Skip empty lines
  [[ -z "$line" ]] && continue

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
  shift 9
  serviceport=$1
  exposeport=$2 
  public_gateway=$3 
  allowed_ips=$4 
  cmd=$5 
  gitrepo=$6 
  branch=$7 
  commit=$8

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
  echo " port: $port"
  echo " cmd: $cmd"
  echo " public_gateway: $public_gateway"
  echo " gitrepo: $gitrepo"
  echo " branch: $branch"
  echo " commit: $commit"
  echo " "
#   "$DEPLOY_SCRIPT" "$name" "$service" "$cpu_requests" "$cpu_limits" "$mem_requests" \ 
#                    "$mem_limits" "$pod_requests" "$pod_limits" "$envs" "$serviceport" \ 
#                    "$exposeport" "$public_gateway" "$allowed_ips" "$cmd" "$gitrepo" \ 
#                    "$branch" "$commit" "$ACCOUNT_ID" "$AWS_REGION" "$NAMESPACE_NAME" \
#                    "$ECR_SECRET_NAME" "$VPC_ID" "$DRY_RUN"
done


