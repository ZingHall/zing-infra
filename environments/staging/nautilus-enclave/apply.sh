#!/bin/bash
# Apply Terraform changes with AWS profile

set -e

PROFILE="${1:-zing-staging}"
EIF_VERSION="${2:-}"

echo "🔧 Applying Terraform with AWS profile: $PROFILE"
echo ""

# Check if terraform is initialized
if [ ! -d ".terraform" ]; then
  echo "⚠️  Terraform not initialized. Running init first..."
  ./init-local.sh "$PROFILE"
  echo ""
fi

# Build terraform apply command
APPLY_CMD="terraform apply -var=\"aws_profile=$PROFILE\" -lock=false"

# Add EIF version if provided
if [ -n "$EIF_VERSION" ]; then
  APPLY_CMD="$APPLY_CMD -var=\"eif_version=$EIF_VERSION\""
  echo "📦 EIF Version: $EIF_VERSION"
fi

echo "🚀 Running: $APPLY_CMD"
echo ""

# Execute terraform apply
eval $APPLY_CMD

echo ""
echo "✅ Terraform apply completed successfully"

