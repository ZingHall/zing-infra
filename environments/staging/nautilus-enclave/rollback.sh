#!/bin/bash
# Quick rollback script for enclave

set -e

OLD_VERSION="${1:-}"
if [ -z "$OLD_VERSION" ]; then
  echo "Usage: $0 <eif_version>"
  echo ""
  echo "Example: $0 abc1234"
  echo ""
  echo "Available versions in S3:"
  aws s3 ls s3://zing-enclave-artifacts-staging/eif/staging/ \
    --profile zing-staging \
    --region ap-northeast-1 2>/dev/null | grep "nitro-" | tail -10 || echo "  (Unable to list, check manually)"
  exit 1
fi

PROFILE="${2:-zing-staging}"

echo "🔄 Rolling back enclave to version: $OLD_VERSION"
echo "📦 Profile: $PROFILE"
echo ""

# Update Terraform
echo "📝 Updating Terraform configuration..."
terraform apply -var="eif_version=$OLD_VERSION" -var="aws_profile=$PROFILE" -auto-approve

# Get ASG name
ASG_NAME=$(terraform output -raw autoscaling_group_name)
echo "📦 Auto Scaling Group: $ASG_NAME"
echo ""

# Trigger instance refresh
echo "🚀 Triggering instance refresh..."
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name "$ASG_NAME" \
  --preferences MinHealthyPercentage=100,InstanceWarmup=300 \
  --profile "$PROFILE" \
  --region ap-northeast-1

echo ""
echo "✅ Rollback initiated"
echo ""
echo "Monitor progress with:"
echo "  aws autoscaling describe-instance-refreshes \\"
echo "    --auto-scaling-group-name $ASG_NAME \\"
echo "    --profile $PROFILE \\"
echo "    --region ap-northeast-1"
