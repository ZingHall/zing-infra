# Zing Watermark Deployment Guide

Step-by-step guide to deploy the Zing Watermark service on Confidential Container ECS cluster.

## Prerequisites Checklist

Before deploying, ensure:

- [ ] **Network VPC Peering** is deployed (ap-northeast-1 ↔ us-east-2)
- [ ] **Nitro Enclave** is deployed and running
- [ ] **mTLS Certificates** are generated and stored in Secrets Manager
- [ ] **Docker Image** is built and pushed to ECR
- [ ] **AWS Credentials** are configured (`zing-staging` profile)

## Step 1: Deploy Network (if not already done)

```bash
cd zing-infra/environments/staging/network
terraform init
terraform plan
terraform apply
```

This creates:
- VPC in ap-northeast-1
- VPC in us-east-2
- VPC Peering connection
- VPC Endpoints in us-east-2

**Verify**: Check that `us_east_2_vpc_id` and `us_east_2_private_subnet_ids` are in outputs.

## Step 2: Generate mTLS Certificates

Create a directory for certificates:

```bash
mkdir -p zing-infra/environments/staging/zing-watermark/certs
cd zing-infra/environments/staging/zing-watermark/certs
```

Generate certificates:

```bash
# Create CA
openssl genrsa -out ecs-ca.key 4096
openssl req -new -x509 -days 365 -key ecs-ca.key -out ecs-ca.crt \
  -subj "/CN=ECS-TEE-CA"

# Create ECS server certificate
openssl genrsa -out ecs-server.key 4096
openssl req -new -key ecs-server.key -out ecs-server.csr \
  -subj "/CN=ECS-Server"

# Sign ECS server certificate
openssl x509 -req -days 365 -in ecs-server.csr -CA ecs-ca.crt -CAkey ecs-ca.key \
  -CAcreateserial -out ecs-server.crt

# Create TEE client certificate (for TEE to connect to ECS)
openssl genrsa -out tee-client.key 4096
openssl req -new -key tee-client.key -out tee-client.csr \
  -subj "/CN=TEE-Client"

# Sign TEE client certificate
openssl x509 -req -days 365 -in tee-client.csr -CA ecs-ca.crt -CAkey ecs-ca.key \
  -CAcreateserial -out tee-client.crt

# Verify certificates
openssl x509 -in ecs-server.crt -text -noout
openssl x509 -in tee-client.crt -text -noout
```

## Step 3: Store Certificates in Secrets Manager

### Option A: Using AWS CLI

```bash
cd zing-infra/environments/staging/zing-watermark

# Step 1: Create JSON file with certificates (must be done first!)
cat > certs/ecs-server-cert.json <<EOF
{
  "server_cert": "$(cat certs/ecs-server.crt | tr '\n' '\\n')",
  "server_key": "$(cat certs/ecs-server.key | tr '\n' '\\n')",
  "ca_cert": "$(cat certs/ecs-ca.crt | tr '\n' '\\n')"
}
EOF

# Step 2: Create secret with the JSON file
aws secretsmanager create-secret \
  --name "ecs-server-mtls-cert" \
  --description "mTLS server certificates for ECS watermark service" \
  --secret-string file://certs/ecs-server-cert.json \
  --region us-east-2 \
  --profile zing-staging

# Alternative: If secret already exists, update it instead:
# aws secretsmanager put-secret-value \
#   --secret-id "ecs-server-mtls-cert" \
#   --secret-string file://certs/ecs-server-cert.json \
#   --region us-east-2 \
#   --profile zing-staging
```

### Option C: Using Terraform

Create `certs.tf`:

```hcl
# Store ECS server certificates in Secrets Manager
resource "aws_secretsmanager_secret" "ecs_server_cert" {
  name        = "ecs-server-mtls-cert"
  description = "mTLS server certificates for ECS watermark service"
  
  tags = {
    Purpose = "mTLS"
    Service = "zing-watermark"
  }
}

resource "aws_secretsmanager_secret_version" "ecs_server_cert" {
  secret_id = aws_secretsmanager_secret.ecs_server_cert.id
  
  secret_string = jsonencode({
    server_cert = file("${path.module}/certs/ecs-server.crt")
    server_key  = file("${path.module}/certs/ecs-server.key")
    ca_cert     = file("${path.module}/certs/ecs-ca.crt")
  })
}
```

## Step 4: Create terraform.tfvars

```bash
cd zing-infra/environments/staging/zing-watermark
```

Create `terraform.tfvars`:

```hcl
# Task configuration
task_cpu     = 512
task_memory  = 1024
desired_count = 1
image_tag    = "latest"

# mTLS server certificates (ECS uses these to accept TEE connections)
# Get ARN after creating secret in Step 3
mtls_certificate_secrets_arns = [
  "arn:aws:secretsmanager:us-east-2:ACCOUNT_ID:secret:ecs-server-mtls-cert-XXXXXX"
]

# Application secrets (if needed)
secrets_arns = [
  # "arn:aws:secretsmanager:us-east-2:ACCOUNT_ID:secret:zing-watermark/database-url-XXXXXX"
]

ssm_parameter_arns = []
```

**Get Account ID**:
```bash
aws sts get-caller-identity --profile zing-staging --query Account --output text
```

**Get Secret ARN**:
```bash
aws secretsmanager describe-secret \
  --secret-id ecs-server-mtls-cert \
  --region us-east-2 \
  --profile zing-staging \
  --query ARN --output text
```

## Step 5: Build and Push Docker Image

### Build Image

```bash
# Navigate to your watermark service directory
cd zing-watermark  # or wherever your Dockerfile is

# Build image
docker build -t zing-watermark:latest .

# Tag for ECR
docker tag zing-watermark:latest \
  ACCOUNT_ID.dkr.ecr.us-east-2.amazonaws.com/zing-watermark:latest
```

### Push to ECR

```bash
# Login to ECR
aws ecr get-login-password --region us-east-2 --profile zing-staging | \
  docker login --username AWS --password-stdin \
  ACCOUNT_ID.dkr.ecr.us-east-2.amazonaws.com

# Push image
docker push ACCOUNT_ID.dkr.ecr.us-east-2.amazonaws.com/zing-watermark:latest
```

**Note**: ECR repository will be created by Terraform, but you need to push the image before deploying the service.

## Step 6: Initialize Terraform

```bash
cd zing-infra/environments/staging/zing-watermark
terraform init
```

This will:
- Download required providers
- Configure S3 backend
- Initialize modules

## Step 7: Plan Deployment

```bash
terraform plan -var-file=terraform.tfvars
```

Review the plan to ensure:
- ✅ Confidential container cluster will be created
- ✅ ECS service will be created
- ✅ Security groups are configured
- ✅ mTLS certificates are referenced

## Step 8: Apply Configuration

```bash
terraform apply -var-file=terraform.tfvars
```

This will create:
1. Confidential Container ECS Cluster (with AMD SEV-SNP)
2. ECR Repository
3. ECS Roles and IAM policies
4. ECS Task Definition
5. ECS Service

**Expected time**: 10-15 minutes (instance launch + ECS agent registration)

## Step 9: Verify Deployment

### Check Cluster Status

```bash
aws ecs describe-clusters \
  --clusters zing-watermark \
  --region us-east-2 \
  --profile zing-staging \
  --include SETTINGS
```

### Check Instances

```bash
aws ecs list-container-instances \
  --cluster zing-watermark \
  --region us-east-2 \
  --profile zing-staging
```

### Check Service Status

```bash
aws ecs describe-services \
  --cluster zing-watermark \
  --services zing-watermark \
  --region us-east-2 \
  --profile zing-staging
```

### Verify mTLS Certificates

```bash
# Get instance ID
INSTANCE_ID=$(aws ecs list-container-instances \
  --cluster zing-watermark \
  --region us-east-2 \
  --profile zing-staging \
  --query 'containerInstanceArns[0]' --output text | \
  xargs -I {} aws ecs describe-container-instances \
    --cluster zing-watermark \
    --container-instances {} \
    --region us-east-2 \
    --profile zing-staging \
    --query 'containerInstances[0].ec2InstanceId' --output text)

# Connect via SSM
aws ssm start-session \
  --target $INSTANCE_ID \
  --region us-east-2 \
  --profile zing-staging

# Check certificates
sudo ls -la /etc/ecs/mtls/
sudo cat /etc/ecs/mtls/server.crt
```

### Check Logs

```bash
aws logs tail /ecs/zing-watermark --follow --region us-east-2 --profile zing-staging
```

## Step 10: Configure TEE to Connect

Update your Enclave configuration to:
1. Use TEE client certificate (`tee-client.crt`, `tee-client.key`)
2. Connect to ECS service endpoint: `https://<ecs-instance-ip>:8080`
3. Verify ECS server certificate using `ecs-ca.crt`

## Troubleshooting

### Instances Not Joining Cluster

1. Check ECS agent logs:
   ```bash
   aws ssm start-session --target i-xxxxx --region us-east-2
   sudo cat /var/log/ecs-init.log
   ```

2. Verify IAM role permissions
3. Check security group allows outbound HTTPS
4. Verify cluster name in `/etc/ecs/ecs.config`

### Service Not Starting

1. Check task definition:
   ```bash
   aws ecs describe-task-definition \
     --task-definition zing-watermark \
     --region us-east-2
   ```

2. Check service events:
   ```bash
   aws ecs describe-services \
     --cluster zing-watermark \
     --services zing-watermark \
     --region us-east-2 \
     --query 'services[0].events[0:5]'
   ```

3. Check task logs:
   ```bash
   aws logs tail /ecs/zing-watermark --follow --region us-east-2
   ```

### mTLS Connection Issues

1. Verify certificates are downloaded:
   ```bash
   sudo ls -la /etc/ecs/mtls/
   ```

2. Test server certificate:
   ```bash
   sudo openssl x509 -in /etc/ecs/mtls/server.crt -text -noout
   ```

3. Check security group allows port 8080 from Enclave

## Next Steps

After successful deployment:

1. **Update Enclave**: Configure TEE to use client certificates and connect to ECS
2. **Test End-to-End**: Send test request through TEE → ECS → TEE flow
3. **Monitor**: Set up CloudWatch alarms for service health
4. **Scale**: Adjust `desired_count` based on load

## Rollback

If deployment fails:

```bash
terraform destroy -var-file=terraform.tfvars
```

**Warning**: This will delete all resources. Ensure you have backups of certificates and configuration.

