# Zing Watermark - Confidential Container ECS Service

This directory contains Terraform configuration for deploying the Zing Watermark service on a **Confidential Container ECS cluster** with AMD SEV-SNP support.

## Architecture

This service implements the **TEE Gateway architecture**:
- **Nitro Enclave (TEE)** = Gateway (receives external requests, decrypts/encrypts)
- **ECS Confidential Container** = Processing Service (receives decrypted data from TEE, processes it)

```
External Client → TEE Gateway → ECS Watermark Service → TEE Gateway → External Client
   (encrypted)     (decrypt)      (process)              (encrypt)      (encrypted)
```

## Prerequisites

1. **Network Resources**: VPC and subnets in `us-east-2` (AMD SEV-SNP supported region)
2. **Enclave Deployment**: Nitro Enclave must be deployed first
3. **mTLS Certificates**: Server certificates for ECS stored in Secrets Manager
4. **Docker Image**: Watermark service image pushed to ECR

## Configuration

### Required Variables

Create `terraform.tfvars`:

```hcl
task_cpu    = 512
task_memory = 1024
desired_count = 1
image_tag   = "latest"

# mTLS server certificates (ECS uses these to accept TEE connections)
mtls_certificate_secrets_arns = [
  "arn:aws:secretsmanager:us-east-2:ACCOUNT_ID:secret:ecs-server-mtls-cert-XXXXXX"
]

# Application secrets
secrets_arns = [
  "arn:aws:secretsmanager:us-east-2:ACCOUNT_ID:secret:zing-watermark/database-url-XXXXXX"
]

ssm_parameter_arns = []
```

### mTLS Certificate Setup

Before deploying, you need to create mTLS server certificates:

1. **Generate Certificates** (see `TEE_GATEWAY_ARCHITECTURE.md`):
   ```bash
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
   ```

2. **Store in Secrets Manager**:
   ```hcl
   resource "aws_secretsmanager_secret" "ecs_server_cert" {
     name = "ecs-server-mtls-cert"
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

## Deployment

### Initialize Terraform

```bash
cd zing-infra/environments/staging/zing-watermark
terraform init
```

### Plan Deployment

```bash
terraform plan -var-file=terraform.tfvars
```

### Apply Configuration

```bash
terraform apply -var-file=terraform.tfvars
```

## Service Configuration

### Container Port

The service listens on port **8080** for mTLS connections from TEE.

### Health Check

Health check endpoint: `http://localhost:8080/health`

### mTLS Certificates

Certificates are automatically mounted from `/etc/ecs/mtls` on the host to `/etc/ecs/mtls` in the container.

### Environment Variables

- `NODE_ENV`: Environment (staging/production)
- `PORT`: Service port (8080)
- `ENCLAVE_ENDPOINT`: TEE Gateway endpoint URL

## Connecting from TEE

The TEE Gateway should connect to:
- **Endpoint**: `zing-watermark.internal:8080` (or use private IP)
- **Protocol**: HTTPS with mTLS
- **Client Certificate**: TEE uses its client certificate
- **Server Certificate**: ECS presents its server certificate

## Monitoring

### CloudWatch Logs

Logs are available at:
- **Log Group**: `/ecs/zing-watermark`
- **Stream Prefix**: `watermark`

### Container Insights

Container Insights is enabled on the cluster for detailed metrics.

### View Logs

```bash
aws logs tail /ecs/zing-watermark --follow --region us-east-2
```

## Scaling

The service uses ECS managed scaling:
- **Min Instances**: 1
- **Max Instances**: 3
- **Desired Capacity**: 1 (configurable)
- **Target Capacity**: 80%

To scale manually:
```bash
aws ecs update-service \
  --cluster zing-watermark \
  --service zing-watermark \
  --desired-count 2 \
  --region us-east-2
```

## Troubleshooting

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

### mTLS Connection Issues

1. Verify certificates are downloaded:
   ```bash
   # SSH into ECS instance
   aws ssm start-session --target i-INSTANCE_ID --region us-east-2
   
   # Check certificates
   sudo ls -la /etc/ecs/mtls/
   ```

2. Test mTLS connection:
   ```bash
   curl -v \
     --cert /etc/ecs/mtls/server.crt \
     --key /etc/ecs/mtls/server.key \
     --cacert /etc/ecs/mtls/ca.crt \
     https://localhost:8080/health
   ```

### No Instances in Cluster

1. Check Auto Scaling Group:
   ```bash
   aws autoscaling describe-auto-scaling-groups \
     --auto-scaling-group-names zing-watermark-asg \
     --region us-east-2
   ```

2. Check instance logs:
   ```bash
   # View initialization logs
   sudo cat /var/log/ecs-init.log
   ```

## Security Considerations

1. **AMD SEV-SNP**: All instances use AMD SEV-SNP for memory encryption
2. **mTLS**: All communication with TEE uses mutual TLS
3. **Private Subnets**: Instances run in private subnets
4. **Security Groups**: Restricted to TEE security group only
5. **Encrypted EBS**: All volumes are encrypted

## Cost Estimation

- **Instance**: m6a.large ~$0.0864/hour
- **EBS**: 50GB gp3 ~$0.004/hour
- **Data Transfer**: Varies by usage

Estimated monthly cost: ~$65-100 (1 instance, minimal traffic)

## Related Documentation

- [Confidential Container Module](../../../modules/confidential-container/README.md)
- [TEE Gateway Architecture](../../../modules/confidential-container/TEE_GATEWAY_ARCHITECTURE.md)
- [mTLS Configuration Examples](../../../modules/confidential-container/MTLS_EXAMPLE.md)

