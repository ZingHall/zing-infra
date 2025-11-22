#!/bin/bash
# Deployment script for zing-watermark service

set -e

PROFILE="${1:-zing-staging}"
ACTION="${2:-apply}"

echo "🚀 Zing Watermark Deployment"
echo "Profile: $PROFILE"
echo "Action: $ACTION"
echo ""

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
  echo "⚠️  terraform.tfvars not found!"
  echo "📝 Creating from example..."
  cp terraform.tfvars.example terraform.tfvars
  echo ""
  echo "❌ Please update terraform.tfvars with your values before continuing"
  echo "   Required: mtls_certificate_secrets_arns"
  exit 1
fi

# Check if certificates exist
if [ ! -f "certs/ecs-server.crt" ] || [ ! -f "certs/ecs-server.key" ] || [ ! -f "certs/ecs-ca.crt" ]; then
  echo "⚠️  mTLS certificates not found in certs/ directory"
  echo ""
  echo "📋 Please generate certificates first:"
  echo "   1. mkdir -p certs"
  echo "   2. Follow instructions in DEPLOYMENT.md Step 2"
  echo ""
  read -p "Continue anyway? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

# Check if terraform is initialized
if [ ! -d ".terraform" ]; then
  echo "🔧 Initializing Terraform..."
  terraform init
  echo ""
fi

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null || echo "")
if [ -z "$ACCOUNT_ID" ]; then
  echo "❌ Failed to get AWS account ID. Check your profile: $PROFILE"
  exit 1
fi

echo "📦 AWS Account ID: $ACCOUNT_ID"
echo ""

# Check if ECR repository exists and has image
if [ "$ACTION" = "apply" ]; then
  echo "🔍 Checking ECR repository..."
  ECR_REPO="zing-watermark"
  ECR_URI="${ACCOUNT_ID}.dkr.ecr.us-east-2.amazonaws.com/${ECR_REPO}"
  
  if aws ecr describe-repositories --repository-names "$ECR_REPO" --region us-east-2 --profile "$PROFILE" &>/dev/null; then
    echo "✅ ECR repository exists"
    
    # Check if image exists
    if aws ecr describe-images --repository-name "$ECR_REPO" --region us-east-2 --profile "$PROFILE" --image-ids imageTag=latest &>/dev/null; then
      echo "✅ Docker image 'latest' found in ECR"
    else
      echo "⚠️  Docker image 'latest' not found in ECR"
      echo "   Please build and push image before deploying:"
      echo "   docker build -t $ECR_URI:latest ."
      echo "   aws ecr get-login-password --region us-east-2 --profile $PROFILE | docker login --username AWS --password-stdin $ECR_URI"
      echo "   docker push $ECR_URI:latest"
      echo ""
      read -p "Continue anyway? (y/N) " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
      fi
    fi
  else
    echo "ℹ️  ECR repository will be created by Terraform"
  fi
  echo ""
fi

# Run terraform command
case "$ACTION" in
  plan)
    echo "📋 Running terraform plan..."
    terraform plan -var-file=terraform.tfvars -var="aws_profile=$PROFILE"
    ;;
  apply)
    echo "🚀 Running terraform apply..."
    terraform apply -var-file=terraform.tfvars -var="aws_profile=$PROFILE"
    ;;
  destroy)
    echo "🗑️  Running terraform destroy..."
    read -p "Are you sure you want to destroy all resources? (yes/no) " -r
    if [[ $REPLY == "yes" ]]; then
      terraform destroy -var-file=terraform.tfvars -var="aws_profile=$PROFILE"
    else
      echo "Cancelled"
      exit 0
    fi
    ;;
  *)
    echo "Usage: $0 [profile] [plan|apply|destroy]"
    echo "  profile: AWS profile (default: zing-staging)"
    echo "  action:  plan, apply, or destroy (default: apply)"
    exit 1
    ;;
esac

echo ""
echo "✅ Deployment completed!"

if [ "$ACTION" = "apply" ]; then
  echo ""
  echo "📊 Next steps:"
  echo "   1. Verify cluster: aws ecs describe-clusters --clusters zing-watermark --region us-east-2 --profile $PROFILE"
  echo "   2. Check service: aws ecs describe-services --cluster zing-watermark --services zing-watermark --region us-east-2 --profile $PROFILE"
  echo "   3. View logs: aws logs tail /ecs/zing-watermark --follow --region us-east-2 --profile $PROFILE"
fi

