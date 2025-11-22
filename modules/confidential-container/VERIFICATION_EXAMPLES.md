# Verification Examples

Examples of how to verify your confidential container ECS cluster deployment.

## Example 1: Basic Verification

After deploying your cluster with Terraform:

```bash
cd zing-infra/modules/confidential-container

# Run verification script
./verify.sh confidential-cluster
```

## Example 2: With AWS Profile

If you're using AWS profiles:

```bash
# Set profile via environment variable
export AWS_PROFILE=zing-staging
./verify.sh confidential-cluster

# Or pass as argument (script will use it)
./verify.sh confidential-cluster zing-staging
```

## Example 3: Specific Region

For non-default regions:

```bash
./verify.sh confidential-cluster zing-staging us-east-2
```

## Example 4: Integration with Terraform

Add verification to your Terraform workflow:

```bash
#!/bin/bash
# deploy-and-verify.sh

set -e

CLUSTER_NAME="confidential-cluster"
AWS_PROFILE="zing-staging"
AWS_REGION="us-east-2"

echo "Deploying cluster..."
terraform apply -var="aws_profile=$AWS_PROFILE"

echo ""
echo "Waiting for instances to launch (5 minutes)..."
sleep 300

echo ""
echo "Verifying deployment..."
./modules/confidential-container/verify.sh \
  "$CLUSTER_NAME" \
  "$AWS_PROFILE" \
  "$AWS_REGION"

if [ $? -eq 0 ]; then
  echo "✅ Deployment verified successfully!"
else
  echo "❌ Verification failed. Check the errors above."
  exit 1
fi
```

## Example 5: CI/CD Integration

For GitHub Actions or similar:

```yaml
# .github/workflows/verify-cluster.yml
name: Verify ECS Cluster

on:
  workflow_dispatch:
    inputs:
      cluster_name:
        description: 'ECS Cluster Name'
        required: true

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-2
      
      - name: Verify cluster
        run: |
          chmod +x zing-infra/modules/confidential-container/verify.sh
          ./zing-infra/modules/confidential-container/verify.sh \
            ${{ inputs.cluster_name }} \
            default \
            us-east-2
```

## Example 6: Manual Step-by-Step Verification

If you prefer manual verification:

```bash
# 1. Check cluster exists
aws ecs describe-clusters \
  --clusters confidential-cluster \
  --region us-east-2 \
  --query 'clusters[0].status'

# 2. List instances
aws ecs list-container-instances \
  --cluster confidential-cluster \
  --region us-east-2

# 3. Get instance details
INSTANCE_ARN=$(aws ecs list-container-instances \
  --cluster confidential-cluster \
  --region us-east-2 \
  --query 'containerInstanceArns[0]' \
  --output text)

# 4. Get EC2 instance ID
EC2_ID=$(aws ecs describe-container-instances \
  --cluster confidential-cluster \
  --container-instances $INSTANCE_ARN \
  --region us-east-2 \
  --query 'containerInstances[0].ec2InstanceId' \
  --output text)

# 5. Verify AMD SEV-SNP
aws ec2 describe-instances \
  --instance-ids $EC2_ID \
  --region us-east-2 \
  --query 'Reservations[0].Instances[0].[InstanceType,CpuOptions.AmdSevSnp,BootMode]' \
  --output table
```

## Example 7: Continuous Monitoring

Set up a cron job to verify cluster health:

```bash
# Add to crontab: crontab -e
# Run every hour
0 * * * * /path/to/verify.sh confidential-cluster zing-staging us-east-2 >> /var/log/cluster-verify.log 2>&1
```

## Expected Output

Successful verification should show:

```
==========================================
Verifying Confidential Container ECS Cluster
==========================================
Cluster Name: confidential-cluster
AWS Profile: zing-staging
AWS Region: us-east-2

1. Checking ECS cluster existence...
✓ Cluster 'confidential-cluster' exists and is ACTIVE

2. Checking cluster settings...
✓ Container Insights is enabled

3. Checking capacity providers...
✓ Capacity providers configured: confidential-cluster-cp

4. Checking EC2 instances in cluster...
✓ Found 2 EC2 instance(s) in cluster
  Checking instance: arn:aws:ecs:us-east-2:123456789:container-instance/...
  ✓ EC2 Instance ID: i-0123456789abcdef0

5. Verifying instance type supports AMD SEV-SNP...
  ✓ Instance type 'm6a.large' supports AMD SEV-SNP

6. Checking AMD SEV-SNP CPU options...
  ✓ AMD SEV-SNP is enabled on instance

7. Checking boot mode...
  ✓ Boot mode is UEFI-compatible: uefi-preferred

8. Checking AMI...
  ✓ AMI: ami-0123456789abcdef0 (al2023-ami-2023.x.x86_64)

9. Checking instance state...
  ✓ Instance is running

10. Checking ECS agent status...
  ✓ ECS agent is connected
  ✓ Container instance status: ACTIVE

12. Checking Auto Scaling Group...
✓ Auto Scaling Group found: confidential-cluster-asg
  Desired: 2, Min: 1, Max: 3, Current: 2
✓ ASG has sufficient instances (2 >= 1)

13. Checking Launch Template...
✓ Launch Template found: lt-0123456789abcdef0
  ✓ AMD SEV-SNP enabled in launch template

==========================================
Verification Summary
==========================================
Passed: 15
Warnings: 0
Failed: 0

✓ All critical checks passed!

Your confidential container ECS cluster is properly configured with AMD SEV-SNP.
```

## Troubleshooting Verification

### Script Fails with "Cluster not found"

- Verify cluster name is correct
- Check AWS region matches deployment region
- Ensure AWS credentials have ECS read permissions

### Script Shows "No instances found"

- Wait 5-10 minutes after deployment for instances to launch
- Check Auto Scaling Group in EC2 console
- Verify subnets have available IP addresses

### AMD SEV-SNP Shows as "disabled"

- Verify instance type is m6a, c6a, or r6a
- Check launch template configuration
- Ensure deployment is in supported region (us-east-2 or eu-west-1)

