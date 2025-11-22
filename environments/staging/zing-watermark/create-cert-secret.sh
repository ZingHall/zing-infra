#!/bin/bash
# Helper script to create mTLS certificate secret in Secrets Manager

set -e

PROFILE="${1:-zing-staging}"
REGION="${2:-us-east-2}"

echo "🔐 Creating mTLS Certificate Secret"
echo "Profile: $PROFILE"
echo "Region: $REGION"
echo ""

# Check if certificates exist
if [ ! -f "certs/ecs-server.crt" ] || [ ! -f "certs/ecs-server.key" ] || [ ! -f "certs/ecs-ca.crt" ]; then
  echo "❌ Error: Certificate files not found!"
  echo ""
  echo "Required files:"
  echo "  - certs/ecs-server.crt"
  echo "  - certs/ecs-server.key"
  echo "  - certs/ecs-ca.crt"
  echo ""
  echo "Please generate certificates first (see DEPLOYMENT.md Step 2)"
  exit 1
fi

# Create JSON file with certificates
echo "📝 Creating JSON file with certificates..."
cat > certs/ecs-server-cert.json <<EOF
{
  "server_cert": "$(cat certs/ecs-server.crt | sed 's/$/\\n/' | tr -d '\n' | sed 's/\\n$//')",
  "server_key": "$(cat certs/ecs-server.key | sed 's/$/\\n/' | tr -d '\n' | sed 's/\\n$//')",
  "ca_cert": "$(cat certs/ecs-ca.crt | sed 's/$/\\n/' | tr -d '\n' | sed 's/\\n$//')"
}
EOF

echo "✅ JSON file created: certs/ecs-server-cert.json"
echo ""

# Check if secret already exists
SECRET_NAME="ecs-server-mtls-cert"
if aws secretsmanager describe-secret \
  --secret-id "$SECRET_NAME" \
  --region "$REGION" \
  --profile "$PROFILE" &>/dev/null; then
  echo "⚠️  Secret '$SECRET_NAME' already exists. Updating..."
  echo ""
  
  aws secretsmanager put-secret-value \
    --secret-id "$SECRET_NAME" \
    --secret-string file://certs/ecs-server-cert.json \
    --region "$REGION" \
    --profile "$PROFILE"
  
  echo "✅ Secret updated successfully"
else
  echo "📦 Creating new secret '$SECRET_NAME'..."
  echo ""
  
  aws secretsmanager create-secret \
    --name "$SECRET_NAME" \
    --description "mTLS server certificates for ECS watermark service" \
    --secret-string file://certs/ecs-server-cert.json \
    --region "$REGION" \
    --profile "$PROFILE"
  
  echo "✅ Secret created successfully"
fi

echo ""
echo "📋 Getting secret ARN..."
SECRET_ARN=$(aws secretsmanager describe-secret \
  --secret-id "$SECRET_NAME" \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query ARN --output text)

echo ""
echo "✅ Secret ARN:"
echo "$SECRET_ARN"
echo ""
echo "📝 Add this ARN to your terraform.tfvars:"
echo "   mtls_certificate_secrets_arns = ["
echo "     \"$SECRET_ARN\""
echo "   ]"
echo ""

