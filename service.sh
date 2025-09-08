#!/bin/bash
set -euo pipefail

# -------- Parameters (new format) --------
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
ACCOUNT_ID=$9
shift 9
AWS_REGION=$1
NAMESPACE_NAME=$2
ECR_SECRET_NAME=$3
VPC_ID=$4
DRY_RUN=$5

# -------- Config --------
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${name}"
BASE_DIR="."
REPO_DIR="${BASE_DIR}/${name}"

mkdir -p "$REPO_DIR"

# -------- Git repo sync --------
if [[ -d "$REPO_DIR/.git" ]]; then
  echo "🔄 Updating repo $name..."
  cd "$REPO_DIR"
  git fetch origin
  git reset --hard "origin/$branch"
else
  echo "📥 Cloning repo $name..."
  git clone -b "$branch" "$gitrepo" "$REPO_DIR"
  cd "$REPO_DIR"
fi

if [[ -n "$commit" && "$commit" != "latest" ]]; then
  git checkout "$commit"
fi

CURRENT_COMMIT=$(git rev-parse HEAD)

# -------- Docker build & push --------
aws ecr describe-repositories --repository-names "${name}" >/dev/null 2>&1 || \
  aws ecr create-repository --repository-name "${name}"

aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

IMAGE_TAG="${ECR_REPO}:${CURRENT_COMMIT}"

cd "$REPO_DIR"

if [[ "$service" == "docker" ]]; then
  echo "🐳 Building using repo Dockerfile..."
  docker build -t "$IMAGE_TAG" .
else
  if [[ "$service" == "python" ]]; then
    DOCKERFILE_TEMPLATE="Docker_python"
  elif [[ "$service" == "node" ]]; then
    DOCKERFILE_TEMPLATE="Docker_js"
  else
    echo "❌ Unknown service type: $service"
    exit 1
  fi

  DOCKERFILE=".Dockerfile.generated"
  cp "$DOCKERFILE_TEMPLATE" "$DOCKERFILE"

  echo "" >> "$DOCKERFILE"
  echo "# Injected environment variables" >> "$DOCKERFILE"

  # Append ENV lines from each env file
  IFS=',' read -ra ENV_FILES <<< "$envs"
  for f in "${ENV_FILES[@]}"; do
    while IFS='=' read -r key value; do
      # skip empty lines and comments
      [[ -z "$key" || "$key" == \#* ]] && continue
      echo "ENV $key=\"$value\"" >> "$DOCKERFILE"
    done < "$f"
  done

  if [[ -n "$cmd" ]]; then
    echo "" >> "$DOCKERFILE"
    echo "CMD [\"/bin/sh\", \"-c\", \"$cmd\"]" >> "$DOCKERFILE"
  fi

  echo "🐳 Building with $DOCKERFILE_TEMPLATE, ENV + CMD override..."
  docker build -f "$DOCKERFILE" -t "$IMAGE_TAG" .
  rm "$DOCKERFILE"
fi

docker push "$IMAGE_TAG"


echo "Pushed $IMAGE_TAG"

# finish docker build


# -------- Check env changes --------
# Generate a ConfigMap from env files

CURRENT_ENVS_HASH=""

if [[DRY_RUN=="false"]]; thenpublicGateway
    kubectl create configmap "${name}-envs" \
        --from-env-file=${envs//,/ --from-env-file=} \
        -o yaml --dry-run=client | kubectl apply -f -

    # Hash of envs (Kubernetes will roll pods if ConfigMap changes and is mounted)
    CURRENT_ENVS_HASH=$(kubectl get configmap "${name}-envs" -o yaml | sha256sum | awk '{print $1}')

    LAST_ENVS_HASH=$(kubectl get configmap "${name}-deploy-state" \
        -o jsonpath='{.data.envsHash}' 2>/dev/null || echo "")

    if [[ "$CURRENT_ENVS_HASH" == "$LAST_ENVS_HASH" && "$CURRENT_COMMIT" == "$LAST_COMMIT" ]]; then
        echo "✅ No changes in code or envs, skipping deployment."
        exit 0
    fi
fi

SERVICE_TYPE="ClusterIp"

# -------- Security Group (public_gateway) --------
if [[ "$public_gateway" == "true" ]]; then
  SERVICE_TYPE="LoadBalancer"
  if [[ -z "$allowed_ips" ]]; then
    echo "❌ public_gateway is true but allowed_ips is empty. Exiting."
    exit 1
  fi

  if [[ "$allowed_ips" == "*" ]]; then
    IPS_LIST="0.0.0.0/0"
  else
    IFS=',' read -ra IPS_LIST <<< "$allowed_ips"
  fi

  SG_NAME="${name}-sg"
  SG_DESC="Security group for service ${name}"
#   VPC_ID=$(aws ec2 describe-vpcs --query 'Vpcs[0].VpcId' --output text)

  # Check if SG exists
  SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${SG_NAME}" \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")

  if [[ "$SG_ID" == "None" || -z "$SG_ID" ]]; then
    echo "🔒 Creating security group $SG_NAME..."
    SG_ID=$(aws ec2 create-security-group --group-name "$SG_NAME" --description "$SG_DESC" --vpc-id "$VPC_ID" --query 'GroupId' --output text)
  fi

  # Revoke old rules
  aws ec2 revoke-security-group-ingress --group-id "$SG_ID" --protocol tcp --port "$exposeport" --cidr 0.0.0.0/0 >/dev/null 2>&1 || true

  # Add rules for allowed IPs
  for ip in "${IPS_LIST[@]}"; do
    echo "➡️  Allowing $ip on port $exposeport"
    aws ec2 authorize-security-group-ingress \
      --group-id "$SG_ID" \
      --protocol tcp \
      --port "$exposeport" \
      --cidr "$ip"
  done
fi


# -------- Helm deployment --------

if [[DRY_RUN=="true"]]; then

    helm template "$name" ./helm-chart \
    --set image.repository="$ECR_REPO" \
    --set image.tag="$CURRENT_COMMIT" \
    --set resources.requests.cpu="$cpu_requests" \
    --set resources.requests.memory="${mem_requests}Mi" \
    --set resources.limits.cpu="$cpu_limits" \
    --set resources.limits.memory="${mem_limits}Mi" \
    --set replicaCount.min="$pod_requests" \
    --set replicaCount.max="$pod_limits" \
    --set service.port="$exposeport" \
    --set service.targetPort="$serviceport" \
    --set service.type="$SERVICE_TYPE" \
    --set deploymentCheckSum="$CURRENT_ENVS_HASH" \
    --set cmd="$cmd" \
    --set envConfigMap="${name}-envs"
fi

if [[DRY_RUN=="false"]]; then
    helm upgrade --install "$name" ./helm-chart \
    --set image.repository="$ECR_REPO" \
    --set image.tag="$CURRENT_COMMIT" \
    --set resources.requests.cpu="$cpu_requests" \
    --set resources.requests.memory="${mem_requests}Mi" \
    --set resources.limits.cpu="$cpu_limits" \
    --set resources.limits.memory="${mem_limits}Mi" \
    --set replicaCount.min="$pod_requests" \
    --set replicaCount.max="$pod_limits" \
    --set service.port="$exposeport" \
    --set service.targetPort="$serviceport" \
    --set service.type="$SERVICE_TYPE" \
    --set deploymentCheckSum="$CURRENT_ENVS_HASH" \
    --set cmd="$cmd" \
    --set envConfigMap="${name}-envs"
fi

if [[DRY_RUN=="false"]]; then
    # -------- Save deployment state --------
    kubectl create configmap "${name}-deploy-state" \
        --from-literal=commit="$CURRENT_COMMIT" \
        --from-literal=envsHash="$CURRENT_ENVS_HASH" \
        -o yaml --dry-run=client | kubectl apply -f -
fi

echo "🚀 Deployment complete for $name"
