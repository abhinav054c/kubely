#!/bin/bash
set -euo pipefail

# === Input Parameters ===
AWS_REGION="${1:-${AWS_REGION:-ap-south-1}}"
EKS_CLUSTER_NAME="${2:-${EKS_CLUSTER_NAME:-my-cluster}}"
AWS_PROFILE="${AWS_PROFILE:-default}"

echo "=== Using parameters ==="
echo "AWS Region     : $AWS_REGION"
echo "EKS Cluster    : $EKS_CLUSTER_NAME"
echo "AWS Profile    : $AWS_PROFILE"

OS="$(uname -s)"

# === Install AWS CLI ===
install_awscli() {
  echo "=== Installing AWS CLI v2 ==="
  if [[ "$OS" == "Linux" ]]; then
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -o awscliv2.zip
    sudo ./aws/install --update
    rm -rf awscliv2.zip aws
  elif [[ "$OS" == "Darwin" ]]; then
    curl -s "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
    sudo installer -pkg AWSCLIV2.pkg -target /
    rm -f AWSCLIV2.pkg
  else
    echo "❌ Unsupported OS: $OS"
    exit 1
  fi
  aws --version
}

# === Install kubectl ===
install_kubectl() {
  echo "=== Installing kubectl ==="
  KUBECTL_VERSION=$(curl -s https://dl.k8s.io/release/stable.txt)

  if [[ "$OS" == "Linux" ]]; then
    curl -sLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  elif [[ "$OS" == "Darwin" ]]; then
    curl -sLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/darwin/amd64/kubectl"
  fi

  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/
  kubectl version --client
}

# === Install Helm ===
install_helm() {
  echo "=== Installing Helm ==="
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  helm version
}

# === Configure AWS credentials ===
configure_aws() {
  echo "=== Configure AWS CLI credentials for profile: $AWS_PROFILE ==="
  read -p "Enter AWS Access Key ID: " AWS_ACCESS_KEY_ID
  read -s -p "Enter AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
  echo
  read -p "Enter AWS Session Token (leave empty if not using MFA/STS): " AWS_SESSION_TOKEN

  aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID" --profile "$AWS_PROFILE"
  aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY" --profile "$AWS_PROFILE"
  if [[ -n "$AWS_SESSION_TOKEN" ]]; then
    aws configure set aws_session_token "$AWS_SESSION_TOKEN" --profile "$AWS_PROFILE"
  fi
  aws configure set region "$AWS_REGION" --profile "$AWS_PROFILE"
  aws configure set output json --profile "$AWS_PROFILE"
}

# === Generate kubeconfig ===
generate_kubeconfig() {
  echo "=== Generating kubeconfig for EKS cluster: $EKS_CLUSTER_NAME ==="
  aws eks update-kubeconfig \
    --region "$AWS_REGION" \
    --name "$EKS_CLUSTER_NAME" \
    --profile "$AWS_PROFILE"
}

# === Main ===
if [[ "$OS" == "Linux" ]]; then
  echo "=== Detected Linux ==="
  sudo apt-get update -y
  sudo apt-get install -y curl unzip tar
elif [[ "$OS" == "Darwin" ]]; then
  echo "=== Detected macOS ==="
  which brew >/dev/null 2>&1 || {
    echo "❌ Homebrew not found. Please install Homebrew first: https://brew.sh/"
    exit 1
  }
  brew install curl unzip
fi

install_awscli
install_kubectl
install_helm
configure_aws
generate_kubeconfig

echo "✅ Installation and configuration complete!"
echo "👉 AWS CLI, kubectl, Helm installed."
echo "👉 kubeconfig set for cluster: $EKS_CLUSTER_NAME"
