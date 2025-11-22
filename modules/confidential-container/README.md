# Confidential Container ECS Cluster Module

This module creates an AWS ECS cluster with EC2 instances that support **AMD SEV-SNP** (Secure Encrypted Virtualization - Secure Nested Paging) for confidential computing. This enables memory encryption and enhanced security for container workloads.

## Quick Start

```hcl
module "confidential_cluster" {
  source = "../../modules/confidential-container"

  name       = "confidential-cluster"
  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids

  instance_type = "m6a.large"
  ami_os        = "amazon-linux-2023"
}
```

**After deployment, verify with:**
```bash
./modules/confidential-container/verify.sh confidential-cluster
```

## Features

- **AMD SEV-SNP Support**: EC2 instances with AMD SEV-SNP enabled for confidential computing
- **UEFI Boot**: Automatic AMI selection with UEFI boot support (Amazon Linux 2023 or Ubuntu 22.04+)
- **ECS Cluster**: Fully configured ECS cluster with EC2 capacity provider
- **Auto Scaling**: Configurable Auto Scaling Group with managed scaling
- **Container Insights**: Optional CloudWatch Container Insights
- **Security**: Encrypted EBS volumes, IMDSv2 required, security groups

## Prerequisites

### Instance Types

Only the following instance types support AMD SEV-SNP:
- **General Purpose**: `m6a.large`, `m6a.xlarge`, `m6a.2xlarge`, `m6a.4xlarge`, `m6a.8xlarge`
- **Compute Optimized**: `c6a.large`, `c6a.xlarge`, `c6a.2xlarge`, `c6a.4xlarge`, `c6a.8xlarge`, `c6a.12xlarge`, `c6a.16xlarge`
- **Memory Optimized**: `r6a.large`, `r6a.xlarge`, `r6a.2xlarge`, `r6a.4xlarge`

### AMI Requirements

The AMI must support:
- **UEFI Boot**: Required for AMD SEV-SNP
- **Operating System**: Amazon Linux 2023 or Ubuntu 22.04+ (23.04+ recommended)

### Regional Availability

AMD SEV-SNP instances are currently available in:
- US East (Ohio) - `us-east-2`
- Europe (Ireland) - `eu-west-1`

⚠️ **Important**: Deploy this module only in supported regions.

## Usage

### Basic Confidential Container Cluster

```hcl
module "confidential_cluster" {
  source = "../../modules/confidential-container"

  name    = "confidential-cluster"
  vpc_id  = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids

  instance_type = "m6a.large"
  ami_os         = "amazon-linux-2023"

  min_size         = 1
  max_size         = 3
  desired_capacity = 1

  tags = {
    Environment = "production"
    Team        = "security"
  }
}
```

### Cluster with Ubuntu

```hcl
module "confidential_cluster" {
  source = "../../modules/confidential-container"

  name    = "confidential-cluster"
  vpc_id  = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids

  instance_type = "c6a.xlarge"
  ami_os         = "ubuntu"

  container_insights_enabled = true
  enable_managed_scaling      = true
  target_capacity             = 80

  tags = var.tags
}
```

### Cluster with Custom AMI

```hcl
module "confidential_cluster" {
  source = "../../modules/confidential-container"

  name    = "confidential-cluster"
  vpc_id  = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids

  instance_type = "m6a.2xlarge"
  ami_id        = "ami-0123456789abcdef0"  # Custom AMI with UEFI boot

  min_size         = 2
  max_size         = 10
  desired_capacity = 2

  enable_auto_scaling      = true
  target_cpu_utilization   = 75
  container_insights_enabled = true

  tags = var.tags
}
```

### Cluster with Nitro Enclave mTLS Support

```hcl
# Create Secrets Manager secrets for mTLS certificates
resource "aws_secretsmanager_secret" "mtls_client_cert" {
  name = "confidential-cluster-mtls-client-cert"
}

resource "aws_secretsmanager_secret_version" "mtls_client_cert" {
  secret_id = aws_secretsmanager_secret.mtls_client_cert.id
  secret_string = jsonencode({
    client_cert = file("${path.module}/certs/client.crt")
    client_key  = file("${path.module}/certs/client.key")
    ca_cert     = file("${path.module}/certs/ca.crt")
  })
}

# Get Enclave security group from existing Enclave deployment
data "aws_security_group" "enclave" {
  name = "nautilus-watermark-staging-enclave-sg"
}

# Create confidential cluster with mTLS support
module "confidential_cluster" {
  source = "../../modules/confidential-container"

  name    = "confidential-cluster"
  vpc_id  = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids

  instance_type = "m6a.large"
  ami_os         = "amazon-linux-2023"

  # Enable mTLS connectivity to Nitro Enclave
  enable_enclave_mtls = true
  
  # Enclave security group for network connectivity
  enclave_security_group_ids = [
    data.aws_security_group.enclave.id
  ]
  
  # Enclave endpoints (host:port format)
  enclave_endpoints = [
    "enclave-internal.example.com:3000",
    "enclave-backup.example.com:3000"
  ]
  
  # mTLS certificate secrets
  mtls_certificate_secrets_arns = [
    aws_secretsmanager_secret.mtls_client_cert.arn
  ]
  
  # Optional: Custom certificate path
  mtls_certificate_path = "/etc/ecs/mtls"

  tags = {
    Environment = "production"
    Team        = "security"
  }
}
```

### Deploying Services to the Cluster

```hcl
# Create confidential cluster
module "confidential_cluster" {
  source = "../../modules/confidential-container"

  name    = "confidential-cluster"
  vpc_id  = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids

  instance_type = "m6a.large"
  ami_os         = "amazon-linux-2023"
}

# Deploy service to confidential cluster
module "api_service" {
  source = "../../modules/aws/ecs-service"

  name       = "api"
  cluster_id = module.confidential_cluster.cluster_id

  # Use EC2 capacity provider (default)
  launch_type = "EC2"  # Note: ecs-service module may need updates for EC2

  # ... other service configuration
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name of the ECS cluster and associated resources | string | - | yes |
| vpc_id | VPC ID where the ECS instances will be deployed | string | - | yes |
| subnet_ids | List of subnet IDs for the Auto Scaling Group | list(string) | - | yes |
| instance_type | EC2 instance type (must support AMD SEV-SNP: m6a, c6a, or r6a series) | string | `"m6a.large"` | no |
| ami_id | AMI ID for the EC2 instances. If not provided, will use latest Amazon Linux 2023 or Ubuntu 22.04+ with UEFI boot support | string | `null` | no |
| ami_os | Operating system for AMI lookup (amazon-linux-2023 or ubuntu) | string | `"amazon-linux-2023"` | no |
| min_size | Minimum number of instances in the Auto Scaling Group | number | `1` | no |
| max_size | Maximum number of instances in the Auto Scaling Group | number | `3` | no |
| desired_capacity | Desired number of instances in the Auto Scaling Group | number | `1` | no |
| root_volume_size | Size of the root EBS volume in GB | number | `30` | no |
| root_volume_type | Type of the root EBS volume | string | `"gp3"` | no |
| root_device_name | Root device name (varies by AMI) | string | `"/dev/xvda"` | no |
| container_insights_enabled | Enable CloudWatch Container Insights for the cluster | bool | `true` | no |
| service_connect_namespace | Service Connect namespace ARN for the cluster | string | `""` | no |
| health_check_grace_period | Health check grace period in seconds | number | `300` | no |
| protect_from_scale_in | Protect instances from scale-in during deployments | bool | `false` | no |
| enable_auto_scaling | Enable Auto Scaling based on CloudWatch metrics | bool | `false` | no |
| target_cpu_utilization | Target CPU utilization for Auto Scaling (0-100) | number | `70` | no |
| enable_managed_scaling | Enable ECS managed scaling for the capacity provider | bool | `true` | no |
| target_capacity | Target capacity percentage for managed scaling (1-100) | number | `100` | no |
| max_scaling_step_size | Maximum scaling step size for managed scaling | number | `10000` | no |
| min_scaling_step_size | Minimum scaling step size for managed scaling | number | `1` | no |
| base_capacity | Base capacity for the capacity provider strategy | number | `0` | no |
| managed_termination_protection | Enable managed termination protection for the capacity provider | bool | `true` | no |
| user_data_extra | Additional user data script content to append | string | `""` | no |
| enable_enclave_mtls | Enable mTLS connectivity to Nitro Enclave | bool | `false` | no |
| enclave_security_group_ids | List of security group IDs for Nitro Enclave instances | list(string) | `[]` | no |
| enclave_endpoints | List of Nitro Enclave endpoint URLs (host:port) for mTLS connections | list(string) | `[]` | no |
| mtls_certificate_secrets_arns | List of Secrets Manager ARNs containing mTLS certificates | list(string) | `[]` | no |
| mtls_certificate_path | Path on instances where mTLS certificates will be stored | string | `"/etc/ecs/mtls"` | no |
| tags | Tags to apply to all resources | map(string) | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster_id | ECS cluster ID |
| cluster_arn | ECS cluster ARN |
| cluster_name | ECS cluster name |
| capacity_provider_name | ECS capacity provider name |
| capacity_provider_arn | ECS capacity provider ARN |
| autoscaling_group_name | Auto Scaling Group name |
| autoscaling_group_arn | Auto Scaling Group ARN |
| launch_template_id | Launch template ID |
| launch_template_arn | Launch template ARN |
| security_group_id | Security group ID for ECS instances |
| iam_role_arn | IAM role ARN for ECS instances |
| iam_instance_profile_arn | IAM instance profile ARN |

## AMD SEV-SNP Limitations

When using AMD SEV-SNP instances, the following limitations apply:

1. **Cannot disable after launch**: Once AMD SEV-SNP is enabled, it cannot be disabled
2. **Instance type changes**: Only allowed to other AMD SEV-SNP-compatible instance types
3. **No hibernation**: Hibernation is not supported
4. **No Nitro Enclaves**: Nitro Enclaves cannot be used on the same instance
5. **No dedicated hosts**: Dedicated hosts are not supported

## Security Features

- **Memory Encryption**: AMD SEV-SNP provides memory encryption at the hardware level
- **Encrypted EBS**: Root volumes are encrypted by default
- **IMDSv2**: Instance metadata service v2 is required (tokens required)
- **Security Groups**: Configurable security groups for network isolation
- **IAM Roles**: Least privilege IAM roles for ECS instances
- **mTLS Support**: Mutual TLS authentication with Nitro Enclave instances

## mTLS Configuration for Nitro Enclave

This module supports establishing secure mTLS connections between ECS containers and Nitro Enclave instances.

### Architecture Patterns

#### Pattern 1: ECS as Client (Default)

In this pattern:
- **Nitro Enclave = Server** (服务端)
  - Listens for incoming connections
  - Validates client certificates from ECS
  
- **Confidential Container ECS = Client** (客户端)
  - Initiates connections to Enclave
  - Uses client certificates stored in Secrets Manager
  - Authenticates itself to the Enclave server

See `MTLS_EXAMPLE.md` for details.

#### Pattern 2: TEE as Gateway (ECS as Server)

In this pattern, **TEE acts as a Gateway** that:
1. Receives encrypted requests from external clients
2. Decrypts sensitive data
3. Calls ECS service for processing
4. Receives processed results
5. Encrypts results and returns to clients

**Connection Flow**:
- External → TEE: HTTPS/mTLS (encrypted)
- TEE → ECS: mTLS (decrypted, authenticated)
- ECS → TEE: mTLS (processed result)
- TEE → External: HTTPS/mTLS (encrypted)

In this pattern:
- **Nitro Enclave = Gateway/Client** (to ECS)
  - Receives external requests (as server)
  - Connects to ECS (as client)
  - Uses client certificate to authenticate to ECS
  
- **Confidential Container ECS = Processing Server** (服务端)
  - Listens for TEE connections
  - Uses server certificate for mTLS
  - Processes decrypted data
  - Returns results to TEE

See `TEE_GATEWAY_ARCHITECTURE.md` for complete implementation guide.

### Prerequisites

1. **Nitro Enclave Deployment**: You must have a Nitro Enclave deployment with mTLS enabled
2. **mTLS Certificates**: Client certificate, private key, and CA certificate stored in AWS Secrets Manager
3. **Network Connectivity**: Security groups must allow traffic between ECS instances and Enclave instances

### Certificate Format

Certificates can be stored in Secrets Manager in two formats:

#### JSON Format (Recommended)

```json
{
  "client_cert": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----",
  "client_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----",
  "ca_cert": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----"
}
```

#### Plain Text Format

Store each certificate as a separate secret or as plain text (will be saved as `cert-0.pem`, `cert-1.pem`, etc.)

### Configuration Steps

1. **Create Secrets Manager Secrets**:

```hcl
resource "aws_secretsmanager_secret" "mtls_cert" {
  name = "confidential-cluster-mtls-cert"
}

resource "aws_secretsmanager_secret_version" "mtls_cert" {
  secret_id = aws_secretsmanager_secret.mtls_cert.id
  secret_string = jsonencode({
    client_cert = file("${path.module}/certs/client.crt")
    client_key  = file("${path.module}/certs/client.key")
    ca_cert     = file("${path.module}/certs/ca.crt")
  })
}
```

2. **Get Enclave Security Group**:

```hcl
data "aws_security_group" "enclave" {
  name = "your-enclave-security-group-name"
}
```

3. **Enable mTLS in Cluster Configuration**:

```hcl
module "confidential_cluster" {
  # ... other configuration ...
  
  enable_enclave_mtls = true
  enclave_security_group_ids = [data.aws_security_group.enclave.id]
  enclave_endpoints = ["enclave.example.com:3000"]
  mtls_certificate_secrets_arns = [
    aws_secretsmanager_secret.mtls_cert.arn
  ]
}
```

### Using mTLS Certificates in Containers

Certificates are automatically downloaded to `/etc/ecs/mtls` (or your custom path) on instance startup. Your container applications can access them:

```python
# Example: Python application using mTLS
import ssl
import requests

cert_path = "/etc/ecs/mtls/client.crt"
key_path = "/etc/ecs/mtls/client.key"
ca_path = "/etc/ecs/mtls/ca.crt"

# Create SSL context
context = ssl.create_default_context(cafile=ca_path)
context.load_cert_chain(cert_path, key_path)

# Make mTLS request to Enclave
response = requests.get(
    "https://enclave.example.com:3000/api/endpoint",
    verify=ca_path,
    cert=(cert_path, key_path)
)
```

### Security Group Rules

When `enable_enclave_mtls` is enabled, the module automatically:
- Adds ingress rules allowing traffic from Enclave security groups
- Adds egress rules allowing traffic to Enclave security groups
- Ensures bidirectional connectivity for mTLS handshake

### Certificate Rotation

To rotate certificates:
1. Update the secret in Secrets Manager
2. Restart ECS instances (or use rolling update)
3. New instances will automatically download updated certificates

### Troubleshooting mTLS

1. **Check certificates are downloaded**:
   ```bash
   sudo ls -la /etc/ecs/mtls/
   ```

2. **Verify certificate format**:
   ```bash
   sudo openssl x509 -in /etc/ecs/mtls/client.crt -text -noout
   ```

3. **Test mTLS connection**:
   ```bash
   curl --cert /etc/ecs/mtls/client.crt \
        --key /etc/ecs/mtls/client.key \
        --cacert /etc/ecs/mtls/ca.crt \
        https://enclave.example.com:3000/health
   ```

4. **Check IAM permissions**:
   ```bash
   aws secretsmanager get-secret-value \
     --secret-id <secret-arn> \
     --region <region>
   ```

5. **Check security group rules**:
   - Verify Enclave security group allows inbound from ECS security group
   - Verify ECS security group allows outbound to Enclave security group

## Cost Considerations

AMD SEV-SNP instances have the same pricing as their non-SEV-SNP counterparts:
- `m6a.large`: ~$0.0864/hour
- `c6a.xlarge`: ~$0.1536/hour
- `r6a.2xlarge`: ~$0.504/hour

**Note**: There is no additional charge for AMD SEV-SNP, but instances are only available in specific regions.

## Best Practices

1. **Region Selection**: Deploy only in supported regions (us-east-2, eu-west-1)
2. **Instance Sizing**: Start with smaller instances (m6a.large) and scale up as needed
3. **AMI Selection**: Use Amazon Linux 2023 for best compatibility, Ubuntu 22.04+ for flexibility
4. **Monitoring**: Enable Container Insights for production workloads
5. **Scaling**: Use managed scaling for automatic capacity management
6. **Security**: Keep security groups restrictive, use private subnets
7. **Tags**: Tag all resources for cost tracking and organization

## Verification

After deploying the cluster, verify that it's properly configured with AMD SEV-SNP support.

### Automated Verification Script

Use the provided verification script to check all aspects of the deployment:

```bash
# Basic usage
./modules/confidential-container/verify.sh <cluster-name>

# With AWS profile and region
./modules/confidential-container/verify.sh confidential-cluster zing-staging us-east-2
```

The script verifies:
- ✅ ECS cluster exists and is active
- ✅ Container Insights configuration
- ✅ Capacity providers are configured
- ✅ EC2 instances are running and joined the cluster
- ✅ Instance types support AMD SEV-SNP (m6a, c6a, r6a)
- ✅ AMD SEV-SNP is enabled on instances
- ✅ UEFI boot mode is configured
- ✅ ECS agent is connected and instances are active
- ✅ Auto Scaling Group configuration
- ✅ Launch Template has AMD SEV-SNP enabled

### Manual Verification Steps

#### 1. Check Cluster Status

```bash
aws ecs describe-clusters \
  --clusters confidential-cluster \
  --include SETTINGS \
  --region us-east-2
```

#### 2. Verify Instances in Cluster

```bash
aws ecs list-container-instances \
  --cluster confidential-cluster \
  --region us-east-2
```

#### 3. Check AMD SEV-SNP is Enabled

```bash
# Get instance IDs
INSTANCE_IDS=$(aws ecs list-container-instances \
  --cluster confidential-cluster \
  --region us-east-2 \
  --query 'containerInstanceArns[*]' \
  --output text | \
  xargs -I {} aws ecs describe-container-instances \
    --cluster confidential-cluster \
    --container-instances {} \
    --region us-east-2 \
    --query 'containerInstances[0].ec2InstanceId' \
    --output text)

# Check AMD SEV-SNP for each instance
for INSTANCE_ID in $INSTANCE_IDS; do
  echo "Checking instance: $INSTANCE_ID"
  aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --region us-east-2 \
    --query 'Reservations[0].Instances[0].[InstanceType,CpuOptions.AmdSevSnp,BootMode]' \
    --output table
done
```

Expected output should show:
- `InstanceType`: m6a.*, c6a.*, or r6a.*
- `AmdSevSnp`: `enabled`
- `BootMode`: `uefi` or `uefi-preferred`

#### 4. Verify ECS Agent Status

```bash
aws ecs describe-container-instances \
  --cluster confidential-cluster \
  --container-instances <container-instance-arn> \
  --region us-east-2 \
  --query 'containerInstances[0].[agentConnected,status]' \
  --output table
```

Expected: `agentConnected: True`, `status: ACTIVE`

#### 5. Check Launch Template

```bash
# Find launch template
LT_ID=$(aws ec2 describe-launch-templates \
  --region us-east-2 \
  --query "LaunchTemplates[?contains(LaunchTemplateName, 'confidential-cluster')].LaunchTemplateId" \
  --output text)

# Verify AMD SEV-SNP in launch template
aws ec2 describe-launch-template-versions \
  --launch-template-id $LT_ID \
  --versions '$Latest' \
  --region us-east-2 \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData.CpuOptions.AmdSevSnp' \
  --output text
```

Expected: `enabled`

#### 6. Verify via AWS Console

1. **ECS Console**: Navigate to ECS → Clusters → Your cluster
   - Verify cluster status is "ACTIVE"
   - Check "Container instances" tab shows running instances
   - Verify "Capacity providers" shows your EC2 capacity provider

2. **EC2 Console**: Navigate to EC2 → Instances
   - Select an instance from your cluster
   - Check "Details" tab:
     - Instance type should be m6a.*, c6a.*, or r6a.*
     - Boot mode should show "uefi" or "uefi-preferred"
   - Check "Security" tab:
     - Under "CPU options", verify "AMD SEV-SNP" shows "Enabled"

3. **Auto Scaling Console**: Navigate to EC2 → Auto Scaling Groups
   - Find your ASG (should contain cluster name)
   - Verify desired/min/max capacity matches your configuration
   - Check instances are healthy

## Troubleshooting

### Instances Not Joining Cluster

1. Check ECS agent logs: `sudo cat /var/log/ecs-init.log`
2. Verify IAM role permissions
3. Check security group rules (outbound HTTPS required)
4. Verify cluster name in `/etc/ecs/ecs.config`

### AMI Not Found

- Ensure you're in a supported region
- Verify AMI supports UEFI boot
- Check AMI owner (Amazon for AL2023, Canonical for Ubuntu)

### Instance Launch Failures

- Verify instance type is in supported list (m6a, c6a, r6a)
- Check subnet availability in supported AZs
- Verify IAM instance profile exists

### AMD SEV-SNP Not Enabled

- Verify instance type supports AMD SEV-SNP
- Check launch template has `cpu_options.amd_sev_snp = "enabled"`
- Ensure you're in a supported region (us-east-2 or eu-west-1)

## Examples

See usage examples above for common configurations.

## Related Modules

- `modules/aws/ecs-service` - Deploy services to ECS clusters
- `modules/aws/ecs-cluster` - Standard ECS cluster (Fargate)
- `modules/aws/enclave` - Nitro Enclaves (alternative confidential computing)

## References

- [AWS AMD SEV-SNP Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/sev-snp.html)
- [ECS EC2 Launch Type](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/launch_type_EC2.html)
- [ECS Capacity Providers](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/cluster-capacity-providers.html)

