# VPC Peering Configuration: ap-northeast-1 ↔ us-east-2

This document describes the VPC peering setup between the main VPC in `ap-northeast-1` and the confidential container VPC in `us-east-2`.

## Architecture

```
┌─────────────────────────────────┐
│  ap-northeast-1 VPC              │
│  CIDR: 10.0.0.0/16               │
│                                  │
│  - Main services (API, Web)     │
│  - Enclave (TEE Gateway)         │
│  - Database                      │
│  - Has NAT Gateway (for internet)│
└──────────────┬───────────────────┘
               │
               │ VPC Peering
               │
┌──────────────▼───────────────────┐
│  us-east-2 VPC                    │
│  CIDR: 10.1.0.0/16                │
│                                   │
│  - Confidential Container ECS     │
│  - AMD SEV-SNP instances          │
│  - No NAT Gateway                 │
│  - VPC Endpoints for AWS services │
└───────────────────────────────────┘
```

## Network Configuration

### ap-northeast-1 VPC
- **CIDR**: `10.0.0.0/16`
- **Public Subnets**: Yes (with Internet Gateway)
- **Private Subnets**: Yes (with NAT Gateway)
- **Purpose**: Main application services

### us-east-2 VPC
- **CIDR**: `10.1.0.0/16`
- **Public Subnets**: No
- **Private Subnets**: Yes (no NAT Gateway)
- **VPC Endpoints**: Yes (for AWS services)
- **Purpose**: Confidential container ECS cluster (AMD SEV-SNP)

## VPC Peering Connection

### Connection Details
- **Requester VPC**: ap-northeast-1 (main VPC)
- **Accepter VPC**: us-east-2 (confidential container VPC)
- **Status**: Auto-accepted via Terraform
- **Cross-Region**: Yes (ap-northeast-1 ↔ us-east-2)

### Routing Configuration

#### ap-northeast-1 → us-east-2
Routes added to:
- All private route tables
- All public route tables (optional)

Destination: `10.1.0.0/16` via VPC Peering Connection

#### us-east-2 → ap-northeast-1
Routes added to:
- All private route tables

Destination: `10.0.0.0/16` via VPC Peering Connection

## VPC Endpoints (us-east-2)

Since us-east-2 VPC has no NAT Gateway, VPC Endpoints are used to access AWS services:

### Gateway Endpoints (Free)
- **S3**: `com.amazonaws.us-east-2.s3` - **Free** (no hourly charge)

### Interface Endpoints (Charged)
- **ECR API**: `com.amazonaws.us-east-2.ecr.api` - For ECR API calls
- **ECR DKR**: `com.amazonaws.us-east-2.ecr.dkr` - For Docker registry
- **CloudWatch Logs**: `com.amazonaws.us-east-2.logs` - For container logs
- **Secrets Manager**: `com.amazonaws.us-east-2.secretsmanager` - For mTLS certificates
- **SSM**: `com.amazonaws.us-east-2.ssm` - For Systems Manager
- **SSM Messages**: `com.amazonaws.us-east-2.ssmmessages` - For SSM messaging
- **EC2 Messages**: `com.amazonaws.us-east-2.ec2messages` - For ECS agent

**Total**: 8 endpoints (1 free Gateway + 7 paid Interface endpoints)

## Security Groups

### Cross-VPC Communication
- **us-east-2 Default SG**: Allows ingress from `10.0.0.0/16` (ap-northeast-1 VPC)
- **VPC Endpoints SG**: Allows HTTPS (443) from `10.1.0.0/16` (us-east-2 VPC)

## Cost Considerations

### VPC Peering
- **Data Transfer**: 
  - Same AZ: $0.01/GB
  - Cross-AZ: $0.01/GB
  - Cross-Region: $0.02/GB (ap-northeast-1 ↔ us-east-2)

### VPC Endpoints
- **Gateway Endpoints** (S3): **Free** (no hourly charge)
- **Interface Endpoints**: ~$0.01/hour per endpoint + data processing charges

**Cost Breakdown**:
- S3 Gateway Endpoint: **$0** (free)
- 7 Interface Endpoints: ~$0.01/hour × 7 × 730 hours/month = **~$51/month**
- Data processing: ~$0.01/GB (varies by usage)

**Estimated monthly cost**: ~$50-70 (7 paid Interface endpoints × 24/7, plus data transfer)

## Deployment

### Step 1: Deploy Network (ap-northeast-1)

```bash
cd zing-infra/environments/staging/network
terraform init
terraform plan
terraform apply
```

This creates:
- Main VPC in ap-northeast-1
- VPC Peering connection request
- Routes in ap-northeast-1

### Step 2: Verify Peering

The peering connection is auto-accepted via the `aws_vpc_peering_connection_accepter` resource.

Check status:
```bash
# In ap-northeast-1
aws ec2 describe-vpc-peering-connections \
  --region ap-northeast-1 \
  --filters "Name=tag:Name,Values=zing-staging-peering-ap-ne-1-to-us-east-2"

# In us-east-2
aws ec2 describe-vpc-peering-connections \
  --region us-east-2 \
  --filters "Name=tag:Name,Values=zing-staging-peering-us-east-2-accepter"
```

### Step 3: Test Connectivity

From a resource in ap-northeast-1:
```bash
# Ping us-east-2 private IP
ping 10.1.0.10  # Replace with actual us-east-2 instance IP
```

From a resource in us-east-2:
```bash
# Ping ap-northeast-1 private IP
ping 10.0.0.10  # Replace with actual ap-northeast-1 instance IP
```

## Troubleshooting

### Peering Connection Not Active

1. Check peering status:
   ```bash
   aws ec2 describe-vpc-peering-connections \
     --vpc-peering-connection-ids pcx-xxxxx
   ```

2. Verify routes are added:
   ```bash
   # ap-northeast-1
   aws ec2 describe-route-tables \
     --filters "Name=vpc-id,Values=vpc-xxxxx" \
     --query 'RouteTables[*].Routes[?DestinationCidrBlock==`10.1.0.0/16`]'
   
   # us-east-2
   aws ec2 describe-route-tables \
     --filters "Name=vpc-id,Values=vpc-xxxxx" \
     --query 'RouteTables[*].Routes[?DestinationCidrBlock==`10.0.0.0/16`]'
   ```

### Cannot Access AWS Services from us-east-2

1. Verify VPC Endpoints are created:
   ```bash
   aws ec2 describe-vpc-endpoints \
     --region us-east-2 \
     --filters "Name=vpc-id,Values=vpc-xxxxx"
   ```

2. Check endpoint security group allows traffic:
   ```bash
   aws ec2 describe-security-groups \
     --region us-east-2 \
     --filters "Name=group-name,Values=zing-staging-us-east-2-vpc-endpoints-sg"
   ```

3. Test endpoint connectivity:
   ```bash
   # From us-east-2 instance
   curl https://ecr.us-east-2.amazonaws.com
   ```

### Security Group Issues

Ensure security groups allow traffic:
- **Source**: ap-northeast-1 VPC CIDR (`10.0.0.0/16`)
- **Destination**: us-east-2 resources
- **Ports**: Required ports (e.g., 8080 for ECS service)

## Best Practices

1. **CIDR Planning**: Use non-overlapping CIDR blocks
2. **Security Groups**: Restrict to specific CIDR blocks, not `0.0.0.0/0`
3. **Monitoring**: Monitor VPC Peering data transfer costs
4. **VPC Endpoints**: Use Gateway endpoints (S3) when possible (free)
5. **Route Tables**: Ensure routes are added to all relevant route tables

## Related Resources

- [AWS VPC Peering Documentation](https://docs.aws.amazon.com/vpc/latest/peering/what-is-vpc-peering.html)
- [VPC Endpoints Documentation](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints.html)
- [Cross-Region VPC Peering](https://docs.aws.amazon.com/vpc/latest/peering/create-vpc-peering-connection.html)

