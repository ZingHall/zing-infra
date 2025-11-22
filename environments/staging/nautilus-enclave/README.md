# Nautilus Enclave - Staging Environment

This directory contains the Terraform configuration for deploying the Nautilus Watermark Service as a Nitro Enclave in the staging environment.

## Overview

This configuration deploys:
- **S3 Bucket**: Stores EIF (Enclave Image Format) files
- **Auto Scaling Group**: Manages EC2 instances running Nitro Enclaves
- **Security Groups**: Network access control
- **IAM Roles**: Permissions for S3 access and Secrets Manager
- **CloudWatch Logs**: Centralized logging

## Prerequisites

1. **Network Infrastructure**: The `network` module must be deployed first
2. **AWS Profile**: Configure `zing-staging` AWS profile
3. **Terraform State**: S3 backend must be configured

## Quick Start

### 1. Initialize Terraform

**For Local Development (with AWS profile):**
```bash
cd zing-infra/environments/staging/nautilus-enclave

# Option 1: Use helper script
./init-local.sh zing-staging

# Option 2: Manual initialization with backend-config
terraform init -backend-config="profile=zing-staging" -reconfigure
```

**For CI/CD (OIDC authentication, no profile needed):**
```bash
# Profile is not needed in CI/CD, GitHub Actions handles authentication
terraform init \
  -backend-config="bucket=terraform-zing-staging" \
  -backend-config="key=nautilus-enclave.tfstate" \
  -backend-config="region=ap-northeast-1" \
  -backend-config="encrypt=true" \
  -backend-config="dynamodb_table=terraform-lock-table"
```

### 2. Plan Changes

**Using helper script (recommended):**
```bash
# Plan with default profile (zing-staging)
./plan.sh

# Plan with specific profile
./plan.sh zing-staging

# Plan with specific EIF version
./plan.sh zing-staging 2dc7685
```

**Manual command:**
```bash
terraform plan -var="aws_profile=zing-staging"
```

### 3. Apply Changes

**Using helper script (recommended):**
```bash
# Apply with default profile (zing-staging)
./apply.sh

# Apply with specific profile
./apply.sh zing-staging

# Apply with specific EIF version
./apply.sh zing-staging 2dc7685
```

**Manual command:**
```bash
terraform apply -var="aws_profile=zing-staging"
```

### 4. Review Variables

Edit `terraform.tfvars` (if exists) or set variables:

```hcl
eif_version = "latest"  # Or specific commit SHA
instance_type = "m5.xlarge"
min_size = 1
max_size = 3
desired_capacity = 1
```

### 3. Plan Deployment

```bash
terraform plan
```

### 4. Apply Configuration

```bash
terraform apply
```

## Deployment Workflow

### Step 1: Build EIF File

In the `nautilus-watermark-service` directory:

```bash
cd ../../../nautilus-watermark-service
make ENCLAVE_APP=zing-watermark
```

This creates `out/nitro.eif` and `out/nitro.pcrs`.

### Step 2: Upload EIF to S3

```bash
COMMIT_SHA=$(git rev-parse --short HEAD)
aws s3 cp out/nitro.eif \
  s3://zing-enclave-artifacts-staging/eif/staging/nitro-${COMMIT_SHA}.eif
```

### Step 3: Update Terraform

Update the `eif_version` variable:

```bash
# Option 1: Update in terraform.tfvars
echo 'eif_version = "abc123"' >> terraform.tfvars

# Option 2: Pass via command line
terraform apply -var="eif_version=abc123"
```

### Step 4: Apply Changes

```bash
terraform apply
```

The Auto Scaling Group will:
1. Launch new instances with the updated EIF version
2. Download the EIF file from S3
3. Start the Nitro Enclave
4. Expose ports via socat
5. Perform health checks

## Configuration

### Variables

Key variables you may want to customize:

| Variable | Description | Default |
|----------|-------------|---------|
| `eif_version` | EIF file version (commit SHA) | `"latest"` |
| `instance_type` | EC2 instance type | `"m5.xlarge"` |
| `min_size` | Minimum instances | `1` (normal operation) |
| `max_size` | Maximum instances | `2` (allows scaling to 2 during deployment) |
| `desired_capacity` | Desired instances | `1` (normal operation, scales to 2 during deployment) |
| `enclave_cpu_count` | vCPUs for enclave | `2` |
| `enclave_memory_mb` | Memory for enclave | `512` |
| `enable_auto_scaling` | Enable auto scaling | `true` |

**Note on Instance Count:**
- **Normal operation**: 1 instance (cost-optimized)
- **During deployment**: CI/CD automatically scales to 2 instances for zero-downtime hotswap
- **After deployment**: Automatically scales back to 1 instance

### Secrets Manager

To grant access to secrets:

```hcl
secrets_arns = [
  "arn:aws:secretsmanager:ap-northeast-1:ACCOUNT_ID:secret:enclave-secrets-*"
]
```

## Monitoring

### CloudWatch Logs

View initialization logs:

```bash
aws logs tail /aws/ec2/nautilus-watermark-staging --follow
```

### Check Enclave Status

SSH into an instance and check:

```bash
sudo nitro-cli describe-enclaves
curl http://localhost:3000/health_check
```

### Auto Scaling Metrics

View in AWS Console:
- EC2 → Auto Scaling Groups → nautilus-watermark-staging-asg
- CloudWatch → Metrics → AWS/AutoScaling

## Troubleshooting

### Re-running User Data Script

**重要**: User data 脚本只在实例首次启动时执行一次。要重新执行 user data，需要：

1. **Terminate 实例**（推荐）：
   - Auto Scaling Group 会自动启动新实例并执行 user data
   - 在 AWS Console: EC2 → Instances → 选择实例 → Instance state → Terminate instance
   - 或使用 CLI:
     ```bash
     # 获取实例 ID
     INSTANCE_ID=$(aws ec2 describe-instances \
       --filters "Name=tag:Name,Values=nautilus-watermark-staging" \
       --query 'Reservations[].Instances[?State.Name==`running`].InstanceId' \
       --output text | head -1)
     
     # Terminate 实例
     aws ec2 terminate-instances --instance-ids $INSTANCE_ID
     ```

2. **通过 Terraform 强制替换**：
   ```bash
   # 修改 launch template（例如更新 user data）
   terraform apply -replace=module.nautilus_enclave.aws_launch_template.enclave
   
   # 然后手动替换 ASG 中的实例
   aws autoscaling start-instance-refresh \
     --auto-scaling-group-name nautilus-watermark-staging-asg
   ```

**注意**:
- ❌ **Reboot** 不会重新执行 user data
- ❌ **Stop/Start** 不会重新执行 user data
- ✅ **Terminate** 会触发新实例启动并执行 user data

### Enclave Not Starting

1. Check CloudWatch Logs:
   ```bash
   aws logs tail /aws/ec2/nautilus-watermark-staging --follow
   ```

2. SSH into instance:
   ```bash
   # Get instance IP from AWS Console or:
   aws ec2 describe-instances \
     --filters "Name=tag:Name,Values=nautilus-watermark-staging" \
     --query 'Reservations[].Instances[].PublicIpAddress'
   
   ssh ec2-user@<IP>
   ```

3. Check enclave status:
   ```bash
   sudo nitro-cli describe-enclaves
   sudo journalctl -u nitro-enclaves
   ```

### EIF File Not Found

1. Verify S3 path:
   ```bash
   aws s3 ls s3://zing-enclave-artifacts-staging/eif/staging/
   ```

2. Check IAM permissions:
   ```bash
   aws iam get-role-policy \
     --role-name nautilus-watermark-staging-enclave-role \
     --policy-name nautilus-watermark-staging-s3-access
   ```

### Health Check Failing

1. Check if enclave is running:
   ```bash
   sudo nitro-cli describe-enclaves
   ```

2. Test health endpoint:
   ```bash
   curl http://localhost:3000/health_check
   ```

3. Check socat processes:
   ```bash
   ps aux | grep socat
   ```

## CI/CD Integration

### GitHub Actions

Add to your workflow:

```yaml
- name: Build and Upload EIF
  run: |
    cd nautilus-watermark-service
    make ENCLAVE_APP=zing-watermark
    
    COMMIT_SHA=$(git rev-parse --short HEAD)
    aws s3 cp out/nitro.eif \
      s3://zing-enclave-artifacts-staging/eif/staging/nitro-${COMMIT_SHA}.eif

- name: Update and Deploy
  run: |
    cd zing-infra/environments/staging/nautilus-enclave
    terraform init
    terraform apply \
      -var="eif_version=${COMMIT_SHA:0:7}" \
      -auto-approve
```

## Cost Optimization

- **Staging**: Use `m5.large` instead of `m5.xlarge` for lower costs
- **Auto Scaling**: Set `min_size=0` to scale down during off-hours
- **Spot Instances**: Consider using Spot instances for non-production

## Security

- EIF files are stored in encrypted S3 bucket
- Instances use IAM roles (no hardcoded credentials)
- Security groups restrict access to VPC CIDR by default
- Enclave init port (3001) is only accessible from localhost

## Related Documentation

- [Enclave Module README](../../../modules/aws/enclave/README.md)
- [Enclave Module Examples](../../../modules/aws/enclave/EXAMPLES.md)
- [Nautilus Documentation](../../../../nautilus-watermark-service/README.md)

