# Quick Verification Guide

This guide provides quick commands to verify your confidential container ECS cluster deployment.

## Prerequisites

- AWS CLI installed and configured
- Appropriate AWS credentials/permissions
- Cluster name from your deployment

## One-Line Verification

```bash
# Replace with your cluster name, profile, and region
./verify.sh confidential-cluster zing-staging us-east-2
```

## Quick Manual Checks

### 1. Cluster Status (30 seconds)

```bash
aws ecs describe-clusters \
  --clusters <cluster-name> \
  --include SETTINGS \
  --region <region> \
  --query 'clusters[0].[status,settings[?name==`containerInsights`].value]' \
  --output table
```

**Expected**: Status = `ACTIVE`, Container Insights = `enabled`

### 2. Instance Count (30 seconds)

```bash
aws ecs list-container-instances \
  --cluster <cluster-name> \
  --region <region> \
  --query 'length(containerInstanceArns)' \
  --output text
```

**Expected**: Number > 0 (matches your desired capacity)

### 3. AMD SEV-SNP Check (1 minute)

```bash
# Get first instance ID
INSTANCE_ID=$(aws ecs list-container-instances \
  --cluster <cluster-name> \
  --region <region> \
  --query 'containerInstanceArns[0]' \
  --output text | \
  xargs -I {} aws ecs describe-container-instances \
    --cluster <cluster-name> \
    --container-instances {} \
    --region <region> \
    --query 'containerInstances[0].ec2InstanceId' \
    --output text)

# Check AMD SEV-SNP
aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --region <region> \
  --query 'Reservations[0].Instances[0].[InstanceType,CpuOptions.AmdSevSnp]' \
  --output table
```

**Expected**: 
- InstanceType starts with `m6a`, `c6a`, or `r6a`
- AmdSevSnp = `enabled`

### 4. ECS Agent Status (30 seconds)

```bash
aws ecs describe-container-instances \
  --cluster <cluster-name> \
  --container-instances $(aws ecs list-container-instances \
    --cluster <cluster-name> \
    --region <region> \
    --query 'containerInstanceArns[0]' \
    --output text) \
  --region <region> \
  --query 'containerInstances[0].[agentConnected,status]' \
  --output table
```

**Expected**: 
- agentConnected = `True`
- status = `ACTIVE`

## Complete Verification Checklist

Run the automated script for comprehensive verification:

```bash
./verify.sh <cluster-name> [aws-profile] [aws-region]
```

The script checks:
- [x] Cluster exists and is active
- [x] Container Insights enabled
- [x] Capacity providers configured
- [x] EC2 instances running
- [x] Instance types support AMD SEV-SNP
- [x] AMD SEV-SNP enabled on instances
- [x] UEFI boot mode configured
- [x] ECS agent connected
- [x] Auto Scaling Group configured
- [x] Launch Template has AMD SEV-SNP

## Common Issues

### No Instances Found

**Symptom**: `Instance Count = 0`

**Solution**: 
- Wait 5-10 minutes for instances to launch
- Check Auto Scaling Group in EC2 console
- Verify subnet has available IPs
- Check security group allows outbound HTTPS

### AMD SEV-SNP Not Enabled

**Symptom**: `AmdSevSnp = null` or `disabled`

**Solution**:
- Verify instance type is m6a, c6a, or r6a
- Check launch template has CPU options configured
- Ensure you're in supported region (us-east-2 or eu-west-1)

### ECS Agent Not Connected

**Symptom**: `agentConnected = False`

**Solution**:
- SSH into instance and check `/var/log/ecs-init.log`
- Verify IAM role has ECS permissions
- Check security group allows outbound to ECS endpoints
- Verify cluster name in `/etc/ecs/ecs.config`

## Next Steps

After verification passes:
1. Deploy your first service to the cluster
2. Monitor Container Insights for metrics
3. Set up CloudWatch alarms for scaling
4. Configure service discovery if needed

