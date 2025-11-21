#!/bin/bash
# Plan Terraform changes with AWS profile

set -e

PROFILE="${1:-zing-staging}"
EIF_VERSION="${2:-}"

echo "🔍 Planning Terraform changes with AWS profile: $PROFILE"
echo ""

# Check if terraform is initialized
if [ ! -d ".terraform" ]; then
  echo "⚠️  Terraform not initialized. Running init first..."
  ./init-local.sh "$PROFILE"
  echo ""
fi

# Build terraform plan command
PLAN_CMD="terraform plan -var=\"aws_profile=$PROFILE\""

# Add EIF version if provided
if [ -n "$EIF_VERSION" ]; then
  PLAN_CMD="$PLAN_CMD -var=\"eif_version=$EIF_VERSION\""
  echo "📦 EIF Version: $EIF_VERSION"
fi

echo "🚀 Running: $PLAN_CMD"
echo ""

# Execute terraform plan
eval $PLAN_CMD

