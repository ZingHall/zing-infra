#!/bin/bash
# Helper script for local development with AWS profile

set -e

PROFILE="${1:-zing-staging}"
ENV="${2:-staging}"

echo "🔧 Initializing Terraform with AWS profile: $PROFILE"
echo "📦 Environment: $ENV"

terraform init \
  -backend-config="profile=$PROFILE" \
  -reconfigure

echo "✅ Terraform initialized successfully"
echo ""
echo "Next steps:"
echo "  terraform plan -var=\"eif_version=latest\""
echo "  terraform apply -var=\"eif_version=latest\""

