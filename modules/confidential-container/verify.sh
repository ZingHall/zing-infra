#!/bin/bash
# Verification script for Confidential Container ECS Cluster
# This script verifies that the cluster is properly deployed with AMD SEV-SNP support

# Don't exit on error - we want to check all items and report results
set +e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="${1:-}"
AWS_PROFILE="${AWS_PROFILE:-default}"
AWS_REGION="${AWS_REGION:-us-east-2}"

if [ -z "$CLUSTER_NAME" ]; then
  echo -e "${RED}Error: Cluster name is required${NC}"
  echo "Usage: $0 <cluster-name> [aws-profile] [aws-region]"
  echo "Example: $0 confidential-cluster zing-staging us-east-2"
  exit 1
fi

if [ -n "$2" ]; then
  AWS_PROFILE="$2"
fi

if [ -n "$3" ]; then
  AWS_REGION="$3"
fi

echo "=========================================="
echo "Verifying Confidential Container ECS Cluster"
echo "=========================================="
echo "Cluster Name: $CLUSTER_NAME"
echo "AWS Profile: $AWS_PROFILE"
echo "AWS Region: $AWS_REGION"
echo ""

# Export AWS profile and region
export AWS_PROFILE=$AWS_PROFILE
export AWS_DEFAULT_REGION=$AWS_REGION

# Track verification results
PASSED=0
FAILED=0
WARNINGS=0

check_pass() {
  echo -e "${GREEN}✓${NC} $1"
  ((PASSED++))
}

check_fail() {
  echo -e "${RED}✗${NC} $1"
  ((FAILED++))
}

check_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
  ((WARNINGS++))
}

# 1. Check if cluster exists
echo "1. Checking ECS cluster existence..."
if aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$AWS_REGION" --query 'clusters[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
  check_pass "Cluster '$CLUSTER_NAME' exists and is ACTIVE"
  CLUSTER_ARN=$(aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$AWS_REGION" --query 'clusters[0].clusterArn' --output text)
else
  check_fail "Cluster '$CLUSTER_NAME' not found or not active"
  exit 1
fi

# 2. Check cluster settings
echo ""
echo "2. Checking cluster settings..."
CONTAINER_INSIGHTS=$(aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$AWS_REGION" --include 'SETTINGS' --query 'clusters[0].settings[?name==`containerInsights`].value' --output text)
if [ "$CONTAINER_INSIGHTS" = "enabled" ]; then
  check_pass "Container Insights is enabled"
else
  check_warn "Container Insights is not enabled"
fi

# 3. Check capacity providers
echo ""
echo "3. Checking capacity providers..."
CAPACITY_PROVIDERS=$(aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$AWS_REGION" --include 'CONFIGURATIONS' --query 'clusters[0].capacityProviders[*]' --output text)
if [ -n "$CAPACITY_PROVIDERS" ]; then
  check_pass "Capacity providers configured: $CAPACITY_PROVIDERS"
else
  check_fail "No capacity providers found"
fi

# 4. Check for EC2 instances in the cluster
echo ""
echo "4. Checking EC2 instances in cluster..."
INSTANCE_COUNT=$(aws ecs list-container-instances --cluster "$CLUSTER_NAME" --region "$AWS_REGION" --query 'length(containerInstanceArns)' --output text)
if [ "$INSTANCE_COUNT" -gt 0 ]; then
  check_pass "Found $INSTANCE_COUNT EC2 instance(s) in cluster"
  
  # Get instance details
  INSTANCE_ARNS=$(aws ecs list-container-instances --cluster "$CLUSTER_NAME" --region "$AWS_REGION" --query 'containerInstanceArns[*]' --output text)
  
  for INSTANCE_ARN in $INSTANCE_ARNS; do
    echo "  Checking instance: $INSTANCE_ARN"
    
    # Get EC2 instance ID
    EC2_INSTANCE_ID=$(aws ecs describe-container-instances --cluster "$CLUSTER_NAME" --container-instances "$INSTANCE_ARN" --region "$AWS_REGION" --query 'containerInstances[0].ec2InstanceId' --output text)
    
    if [ -n "$EC2_INSTANCE_ID" ] && [ "$EC2_INSTANCE_ID" != "None" ]; then
      check_pass "  EC2 Instance ID: $EC2_INSTANCE_ID"
      
      # 5. Check instance type (must be m6a, c6a, or r6a)
      echo ""
      echo "5. Verifying instance type supports AMD SEV-SNP..."
      INSTANCE_TYPE=$(aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" --region "$AWS_REGION" --query 'Reservations[0].Instances[0].InstanceType' --output text)
      if echo "$INSTANCE_TYPE" | grep -qE "^(m6a|c6a|r6a)\."; then
        check_pass "  Instance type '$INSTANCE_TYPE' supports AMD SEV-SNP"
      else
        check_fail "  Instance type '$INSTANCE_TYPE' does NOT support AMD SEV-SNP (must be m6a, c6a, or r6a)"
      fi
      
      # 6. Check CPU options for AMD SEV-SNP
      echo ""
      echo "6. Checking AMD SEV-SNP CPU options..."
      AMD_SEV_SNP=$(aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" --region "$AWS_REGION" --query 'Reservations[0].Instances[0].CpuOptions.AmdSevSnp' --output text)
      if [ "$AMD_SEV_SNP" = "enabled" ]; then
        check_pass "  AMD SEV-SNP is enabled on instance"
      else
        check_fail "  AMD SEV-SNP is NOT enabled on instance (found: $AMD_SEV_SNP)"
      fi
      
      # 7. Check boot mode (UEFI)
      echo ""
      echo "7. Checking boot mode..."
      BOOT_MODE=$(aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" --region "$AWS_REGION" --query 'Reservations[0].Instances[0].BootMode' --output text)
      if [ "$BOOT_MODE" = "uefi" ] || [ "$BOOT_MODE" = "uefi-preferred" ]; then
        check_pass "  Boot mode is UEFI-compatible: $BOOT_MODE"
      else
        check_warn "  Boot mode: $BOOT_MODE (should be uefi or uefi-preferred)"
      fi
      
      # 8. Check AMI
      echo ""
      echo "8. Checking AMI..."
      AMI_ID=$(aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" --region "$AWS_REGION" --query 'Reservations[0].Instances[0].ImageId' --output text)
      AMI_NAME=$(aws ec2 describe-images --image-ids "$AMI_ID" --region "$AWS_REGION" --query 'Images[0].Name' --output text)
      check_pass "  AMI: $AMI_ID ($AMI_NAME)"
      
      # 9. Check instance state
      echo ""
      echo "9. Checking instance state..."
      INSTANCE_STATE=$(aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" --region "$AWS_REGION" --query 'Reservations[0].Instances[0].State.Name' --output text)
      if [ "$INSTANCE_STATE" = "running" ]; then
        check_pass "  Instance is running"
      else
        check_fail "  Instance state: $INSTANCE_STATE (expected: running)"
      fi
      
      # 10. Check ECS agent status
      echo ""
      echo "10. Checking ECS agent status..."
      AGENT_CONNECTED=$(aws ecs describe-container-instances --cluster "$CLUSTER_NAME" --container-instances "$INSTANCE_ARN" --region "$AWS_REGION" --query 'containerInstances[0].agentConnected' --output text)
      if [ "$AGENT_CONNECTED" = "True" ]; then
        check_pass "  ECS agent is connected"
      else
        check_fail "  ECS agent is NOT connected"
      fi
      
      # 11. Check instance status
      INSTANCE_STATUS=$(aws ecs describe-container-instances --cluster "$CLUSTER_NAME" --container-instances "$INSTANCE_ARN" --region "$AWS_REGION" --query 'containerInstances[0].status' --output text)
      if [ "$INSTANCE_STATUS" = "ACTIVE" ]; then
        check_pass "  Container instance status: ACTIVE"
      else
        check_fail "  Container instance status: $INSTANCE_STATUS (expected: ACTIVE)"
      fi
      
    else
      check_fail "  Could not retrieve EC2 instance ID"
    fi
  done
else
  check_fail "No EC2 instances found in cluster"
  echo "  Note: Instances may still be launching. Wait a few minutes and try again."
fi

# 12. Check Auto Scaling Group
echo ""
echo "12. Checking Auto Scaling Group..."
ASG_NAME=$(aws autoscaling describe-auto-scaling-groups --region "$AWS_REGION" --query "AutoScalingGroups[?contains(Tags[?Key=='Name'].Value, '$CLUSTER_NAME')].AutoScalingGroupName" --output text | head -1)
if [ -n "$ASG_NAME" ] && [ "$ASG_NAME" != "None" ]; then
  check_pass "Auto Scaling Group found: $ASG_NAME"
  
  ASG_DESIRED=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --region "$AWS_REGION" --query 'AutoScalingGroups[0].DesiredCapacity' --output text)
  ASG_MIN=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --region "$AWS_REGION" --query 'AutoScalingGroups[0].MinSize' --output text)
  ASG_MAX=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --region "$AWS_REGION" --query 'AutoScalingGroups[0].MaxSize' --output text)
  ASG_CURRENT=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --region "$AWS_REGION" --query 'AutoScalingGroups[0].Instances | length(@)' --output text)
  
  echo "  Desired: $ASG_DESIRED, Min: $ASG_MIN, Max: $ASG_MAX, Current: $ASG_CURRENT"
  
  if [ "$ASG_CURRENT" -ge "$ASG_MIN" ]; then
    check_pass "ASG has sufficient instances ($ASG_CURRENT >= $ASG_MIN)"
  else
    check_warn "ASG has fewer instances than minimum ($ASG_CURRENT < $ASG_MIN)"
  fi
else
  check_warn "Auto Scaling Group not found (may be using different naming)"
fi

# 13. Check Launch Template
echo ""
echo "13. Checking Launch Template..."
LT_ID=$(aws ec2 describe-launch-templates --region "$AWS_REGION" --query "LaunchTemplates[?contains(LaunchTemplateName, '$CLUSTER_NAME')].LaunchTemplateId" --output text | head -1)
if [ -n "$LT_ID" ] && [ "$LT_ID" != "None" ]; then
  check_pass "Launch Template found: $LT_ID"
  
  # Check launch template CPU options
  LT_AMD_SEV_SNP=$(aws ec2 describe-launch-template-versions --launch-template-id "$LT_ID" --versions '$Latest' --region "$AWS_REGION" --query 'LaunchTemplateVersions[0].LaunchTemplateData.CpuOptions.AmdSevSnp' --output text)
  if [ "$LT_AMD_SEV_SNP" = "enabled" ]; then
    check_pass "  AMD SEV-SNP enabled in launch template"
  else
    check_fail "  AMD SEV-SNP NOT enabled in launch template (found: $LT_AMD_SEV_SNP)"
  fi
else
  check_warn "Launch Template not found"
fi

# Summary
echo ""
echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ All critical checks passed!${NC}"
  echo ""
  echo "Your confidential container ECS cluster is properly configured with AMD SEV-SNP."
  exit 0
else
  echo -e "${RED}✗ Some checks failed. Please review the errors above.${NC}"
  exit 1
fi

