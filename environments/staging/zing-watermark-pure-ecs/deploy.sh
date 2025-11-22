#!/bin/bash

# Deploy ECS cluster in ap-northeast-1
# This script initializes and applies Terraform configuration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🚀 Deploying ECS cluster in ap-northeast-1..."
echo ""

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
  echo "📦 Initializing Terraform..."
  terraform init
  echo ""
fi

# Plan
echo "📋 Planning Terraform changes..."
terraform plan
echo ""

# Ask for confirmation
read -p "Do you want to apply these changes? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "❌ Deployment cancelled."
  exit 1
fi

# Apply
echo "✅ Applying Terraform configuration..."
terraform apply

echo ""
echo "🎉 ECS cluster deployment completed!"
echo ""
echo "Cluster outputs:"
terraform output

