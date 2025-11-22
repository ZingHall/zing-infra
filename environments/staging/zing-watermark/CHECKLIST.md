# Deployment Checklist

## Current Status

- ✅ **Certificates created** (ecs-ca.crt, ecs-server.crt, ecs-server.key, tee-client.crt)
- ❌ **terraform.tfvars** - Missing
- ❌ **Secrets Manager secret** - Not created
- ❓ **Docker image** - Need to verify
- ❓ **Network VPC peering** - Need to verify

## Steps to Complete

### 1. Create Secret in Secrets Manager

```bash
cd /Users/gary/zing/zing-infra/environments/staging/zing-watermark
./create-cert-secret.sh zing-staging
```

This will:
- Create the JSON file with certificates
- Create/update the secret in Secrets Manager
- Output the secret ARN

### 2. Create terraform.tfvars

After step 1, copy the secret ARN and create `terraform.tfvars`:

```bash
cp terraform.tfvars.example terraform.tfvars
# Then edit terraform.tfvars and add the secret ARN
```

### 3. Build and Push Docker Image

You need a Docker image for the watermark service. Check if you have:
- A `zing-watermark` service directory with a Dockerfile
- Or if the service is part of another project

If the image doesn't exist, you'll need to:
1. Create a Dockerfile for the watermark service
2. Build the image
3. Push to ECR

### 4. Verify Network Prerequisites

Ensure the network VPC peering is deployed:

```bash
cd /Users/gary/zing/zing-infra/environments/staging/network
terraform output us_east_2_vpc_id
```

### 5. Deploy

```bash
cd /Users/gary/zing/zing-infra/environments/staging/zing-watermark
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

