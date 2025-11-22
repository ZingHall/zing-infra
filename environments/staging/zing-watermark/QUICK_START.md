# Quick Start - Zing Watermark Deployment

## Prerequisites

✅ Network VPC peering deployed  
✅ Nitro Enclave deployed  
✅ AWS profile `zing-staging` configured  

## Step-by-Step Deployment

### 1. Generate mTLS Certificates

```bash
cd zing-infra/environments/staging/zing-watermark
mkdir -p certs
cd certs

# Create CA
openssl genrsa -out ecs-ca.key 4096
openssl req -new -x509 -days 365 -key ecs-ca.key -out ecs-ca.crt \
  -subj "/CN=ECS-TEE-CA"

# Create ECS server certificate
openssl genrsa -out ecs-server.key 4096
openssl req -new -key ecs-server.key -out ecs-server.csr \
  -subj "/CN=ECS-Server"
openssl x509 -req -days 365 -in ecs-server.csr -CA ecs-ca.crt -CAkey ecs-ca.key \
  -CAcreateserial -out ecs-server.crt

# Create TEE client certificate
openssl genrsa -out tee-client.key 4096
openssl req -new -key tee-client.key -out tee-client.csr \
  -subj "/CN=TEE-Client"
openssl x509 -req -days 365 -in tee-client.csr -CA ecs-ca.crt -CAkey ecs-ca.key \
  -CAcreateserial -out tee-client.crt
```

### 2. Create terraform.tfvars

```bash
cd ..
cp terraform.tfvars.example terraform.tfvars
```

### 3. Deploy Certificates to Secrets Manager

**Option A: Using helper script (Recommended)**

```bash
# Run the helper script
./create-cert-secret.sh zing-staging

# It will output the secret ARN - copy it for terraform.tfvars
```

**Option B: Using Terraform**

```bash
# Initialize Terraform (first time only)
terraform init

# Apply certs.tf to create secret
terraform apply -target=aws_secretsmanager_secret.ecs_server_cert \
  -target=aws_secretsmanager_secret_version.ecs_server_cert

# Get the secret ARN
terraform output ecs_server_cert_secret_arn
```

Update `terraform.tfvars` with the ARN:

```hcl
mtls_certificate_secrets_arns = [
  "arn:aws:secretsmanager:us-east-2:ACCOUNT_ID:secret:ecs-server-mtls-cert-XXXXXX"
]
```

### 4. Build and Push Docker Image

```bash
# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile zing-staging --query Account --output text)

# Login to ECR
aws ecr get-login-password --region us-east-2 --profile zing-staging | \
  docker login --username AWS --password-stdin \
  ${ACCOUNT_ID}.dkr.ecr.us-east-2.amazonaws.com

# Build and push (from your watermark service directory)
docker build -t zing-watermark:latest .
docker tag zing-watermark:latest \
  ${ACCOUNT_ID}.dkr.ecr.us-east-2.amazonaws.com/zing-watermark:latest
docker push ${ACCOUNT_ID}.dkr.ecr.us-east-2.amazonaws.com/zing-watermark:latest
```

### 5. Deploy Infrastructure

```bash
# Using deployment script (recommended)
./deploy.sh zing-staging apply

# Or manually
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

### 6. Verify Deployment

```bash
# Check cluster
aws ecs describe-clusters \
  --clusters zing-watermark \
  --region us-east-2 \
  --profile zing-staging

# Check service
aws ecs describe-services \
  --cluster zing-watermark \
  --services zing-watermark \
  --region us-east-2 \
  --profile zing-staging

# Check logs
aws logs tail /ecs/zing-watermark --follow \
  --region us-east-2 \
  --profile zing-staging
```

## Next Steps

1. **Configure TEE**: Update Enclave to use `tee-client.crt` and `tee-client.key`
2. **Test Connection**: Verify TEE can connect to ECS via mTLS
3. **Monitor**: Set up CloudWatch alarms

## Troubleshooting

See [DEPLOYMENT.md](./DEPLOYMENT.md) for detailed troubleshooting steps.

