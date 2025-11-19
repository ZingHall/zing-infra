# Nitro Enclave Module

A Terraform module for deploying AWS Nitro Enclaves on EC2 instances with Auto Scaling, health checks, and automated deployment from S3.

## Features

- ✅ **Auto Scaling**: Automatically scale instances based on CPU/memory utilization
- ✅ **S3 Integration**: Automatically download and deploy EIF files from S3
- ✅ **Health Checks**: Built-in health check and automatic recovery
- ✅ **Security**: IAM roles, security groups, encrypted volumes
- ✅ **Monitoring**: CloudWatch Logs integration
- ✅ **High Availability**: Multi-AZ deployment support
- ✅ **Zero-Downtime**: Rolling updates with Auto Scaling Group

## Architecture

```
┌─────────────────────────────────────────┐
│         Auto Scaling Group              │
│  ┌──────────┐  ┌──────────┐           │
│  │ EC2 (AZ1)│  │ EC2 (AZ2)│  ...      │
│  │          │  │          │           │
│  │ Enclave  │  │ Enclave  │           │
│  │ :3000    │  │ :3000    │           │
│  └──────────┘  └──────────┘           │
└─────────────────────────────────────────┘
         ↓              ↓
    ┌─────────────────────────┐
    │   Application Load      │
    │   Balancer (Optional)   │
    └─────────────────────────┘
```

## Usage

### Basic Example

```hcl
module "nautilus_enclave" {
  source = "../../../modules/aws/enclave"

  name    = "nautilus-watermark"
  vpc_id  = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  s3_bucket_name = "zing-enclave-artifacts"
  s3_bucket_arn  = "arn:aws:s3:::zing-enclave-artifacts"
  eif_version    = "abc123"  # Commit SHA or version tag

  instance_type = "m5.xlarge"
  min_size      = 1
  max_size      = 3
  desired_capacity = 2

  allowed_cidr_blocks = ["10.0.0.0/8"]

  tags = {
    Environment = "production"
    Application = "nautilus-watermark"
  }
}
```

### With Secrets Manager

```hcl
module "nautilus_enclave" {
  source = "../../../modules/aws/enclave"

  name    = "nautilus-watermark"
  vpc_id  = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  s3_bucket_name = "zing-enclave-artifacts"
  s3_bucket_arn  = "arn:aws:s3:::zing-enclave-artifacts"
  eif_version    = "abc123"

  secrets_arns = [
    "arn:aws:secretsmanager:us-east-1:123456789:secret:enclave-secrets-*"
  ]

  tags = {
    Environment = "production"
  }
}
```

### With Auto Scaling

```hcl
module "nautilus_enclave" {
  source = "../../../modules/aws/enclave"

  name    = "nautilus-watermark"
  vpc_id  = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  s3_bucket_name = "zing-enclave-artifacts"
  s3_bucket_arn  = "arn:aws:s3:::zing-enclave-artifacts"

  enable_auto_scaling = true
  target_cpu_utilization = 70
  target_memory_utilization = 80

  min_size = 2
  max_size = 10
  desired_capacity = 3

  tags = {
    Environment = "production"
  }
}
```

### With ALB Integration

```hcl
# Create ALB target group
resource "aws_lb_target_group" "enclave" {
  name     = "nautilus-enclave"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health_check"
    matcher             = "200"
  }
}

# Register ASG with target group
resource "aws_autoscaling_attachment" "enclave" {
  autoscaling_group_name = module.nautilus_enclave.autoscaling_group_id
  lb_target_group_arn    = aws_lb_target_group.enclave.arn
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| aws | >= 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | Name prefix for all resources | `string` | n/a | yes |
| vpc_id | VPC ID where instances will be deployed | `string` | n/a | yes |
| subnet_ids | List of subnet IDs for Auto Scaling Group | `list(string)` | n/a | yes |
| s3_bucket_name | S3 bucket name where EIF files are stored | `string` | n/a | yes |
| s3_bucket_arn | S3 bucket ARN for IAM permissions | `string` | n/a | yes |
| instance_type | EC2 instance type (must support Nitro Enclaves) | `string` | `"m5.xlarge"` | no |
| min_size | Minimum number of instances | `number` | `1` | no |
| max_size | Maximum number of instances | `number` | `3` | no |
| desired_capacity | Desired number of instances | `number` | `1` | no |
| eif_version | Version/tag of the EIF file to deploy | `string` | `"latest"` | no |
| eif_path | S3 path to the EIF file | `string` | `"eif/staging"` | no |
| enclave_cpu_count | Number of vCPUs for the enclave | `number` | `2` | no |
| enclave_memory_mb | Memory in MB for the enclave | `number` | `512` | no |
| enclave_port | Port on which the enclave listens | `number` | `3000` | no |
| allowed_cidr_blocks | CIDR blocks allowed to access enclave | `list(string)` | `["0.0.0.0/0"]` | no |
| secrets_arns | Secrets Manager ARNs for instance access | `list(string)` | `[]` | no |
| enable_auto_scaling | Enable Auto Scaling based on metrics | `bool` | `true` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| autoscaling_group_id | ID of the Auto Scaling Group |
| autoscaling_group_name | Name of the Auto Scaling Group |
| launch_template_id | ID of the Launch Template |
| security_group_id | ID of the Security Group |
| iam_role_arn | ARN of the IAM role |
| cloudwatch_log_group_name | Name of the CloudWatch Log Group |
| enclave_port | Port on which the enclave listens |

## Deployment Workflow

### 1. Build EIF File

```bash
cd nautilus-watermark-service
make ENCLAVE_APP=zing-watermark
# EIF file will be in out/nitro.eif
```

### 2. Upload to S3

```bash
COMMIT_SHA=$(git rev-parse --short HEAD)
aws s3 cp out/nitro.eif \
  s3://zing-enclave-artifacts/eif/staging/nitro-${COMMIT_SHA}.eif
```

### 3. Update Terraform

```hcl
module "nautilus_enclave" {
  # ...
  eif_version = "abc123"  # Use the commit SHA
}
```

### 4. Apply Terraform

```bash
terraform apply
```

The instances will automatically:
1. Download the EIF file from S3
2. Start the Nitro Enclave
3. Expose ports via socat
4. Perform health checks

## CI/CD Integration

### GitHub Actions Example

```yaml
- name: Upload EIF to S3
  run: |
    COMMIT_SHA=$(git rev-parse --short HEAD)
    aws s3 cp out/nitro.eif \
      s3://zing-enclave-artifacts/eif/staging/nitro-${COMMIT_SHA}.eif

- name: Update Terraform EIF Version
  run: |
    # Update eif_version in terraform variables
    sed -i "s/eif_version = \".*\"/eif_version = \"${COMMIT_SHA}\"/" terraform/enclave.tf

- name: Apply Terraform
  run: |
    cd terraform
    terraform apply -auto-approve
```

## Health Checks

The module includes built-in health checks:

1. **Instance Health**: Auto Scaling Group monitors instance health
2. **Enclave Health**: User data script checks `/health_check` endpoint
3. **ALB Health**: If integrated with ALB, target group health checks

## Monitoring

### CloudWatch Logs

All initialization logs are available in:
```
/aws/ec2/{name}
```

### CloudWatch Metrics

Auto Scaling Group provides:
- `GroupDesiredCapacity`
- `GroupInServiceInstances`
- `GroupTotalInstances`
- `CPUUtilization`
- `MemoryUtilization`

## Security

### IAM Permissions

The module creates an IAM role with:
- S3 read access for EIF files
- Secrets Manager access (if configured)
- CloudWatch Logs write access

### Network Security

- Security group restricts access to specified CIDR blocks
- Enclave init port (3001) is only accessible from localhost
- Enclave service port (3000) is accessible from allowed CIDR blocks

### Encryption

- EBS volumes are encrypted at rest
- EIF files should be encrypted in S3

## Troubleshooting

### Enclave Not Starting

1. Check CloudWatch Logs: `/aws/ec2/{name}`
2. SSH into instance and check:
   ```bash
   sudo nitro-cli describe-enclaves
   sudo journalctl -u nitro-enclaves
   ```

### EIF File Not Found

1. Verify S3 path: `s3://{bucket}/{eif_path}/nitro-{version}.eif`
2. Check IAM permissions for S3 access
3. Verify EIF version matches the deployed version

### Health Check Failing

1. Check if enclave is running: `sudo nitro-cli describe-enclaves`
2. Test health endpoint: `curl http://localhost:3000/health_check`
3. Check socat processes: `ps aux | grep socat`

## Limitations

- **Fargate Not Supported**: Nitro Enclaves require EC2 instances
- **Instance Types**: Only specific instance types support Nitro Enclaves
- **Regional Availability**: Some instance types may not be available in all regions

## Cost Optimization

- Use Spot Instances for non-production environments
- Enable Auto Scaling to scale down during low traffic
- Use smaller instance types if CPU/memory requirements allow

## Related Modules

- `ecs-cluster` - ECS cluster for other services
- `https-alb` - Application Load Balancer
- `ecs-service` - ECS services (non-enclave)

## License

Apache 2.0

