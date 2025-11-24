#!/bin/bash
# Fast destroy script - stops ECS service before Terraform destroy

set -e

PROFILE="${1:-zing-staging}"
REGION="ap-northeast-1"
CLUSTER="zing-watermark-pure-ecs"
SERVICE="zing-watermark"

echo "🚀 Fast destroy: Stopping ECS service first..."
echo "Using AWS profile: $PROFILE"
echo ""

# 1. 停止 ECS Service (設置 desired_count 為 0)
echo "📉 Setting desired count to 0..."
aws ecs update-service \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --desired-count 0 \
  --force-new-deployment \
  --profile "$PROFILE" \
  --region "$REGION" > /dev/null 2>&1 || {
  echo "⚠️  Service may not exist or already stopped"
}

# 2. 等待服務穩定（任務停止）
echo "⏳ Waiting for service to stop (max 2 minutes)..."
TIMEOUT=120
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
  RUNNING_TASKS=$(aws ecs describe-services \
    --cluster "$CLUSTER" \
    --services "$SERVICE" \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query 'services[0].runningCount' \
    --output text 2>/dev/null || echo "0")
  
  if [ "$RUNNING_TASKS" = "0" ] || [ "$RUNNING_TASKS" = "None" ]; then
    echo "✅ All tasks stopped"
    break
  fi
  
  echo "  Still running: $RUNNING_TASKS tasks..."
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

# 3. 強制停止所有剩餘任務（如果有）
echo ""
echo "🗑️  Checking for remaining tasks..."
TASK_ARNS=$(aws ecs list-tasks \
  --cluster "$CLUSTER" \
  --service-name "$SERVICE" \
  --profile "$PROFILE" \
  --region "$REGION" \
  --query 'taskArns[]' \
  --output text 2>/dev/null || echo "")

if [ -n "$TASK_ARNS" ] && [ "$TASK_ARNS" != "None" ]; then
  echo "  Found tasks, stopping them..."
  for TASK_ARN in $TASK_ARNS; do
    aws ecs stop-task \
      --cluster "$CLUSTER" \
      --task "$TASK_ARN" \
      --profile "$PROFILE" \
      --region "$REGION" > /dev/null 2>&1 || true
  done
  echo "✅ All tasks force-stopped"
  sleep 5
else
  echo "✅ No running tasks found"
fi

# 4. 運行 Terraform destroy
echo ""
echo "🗑️  Running Terraform destroy..."
terraform destroy -var="aws_profile=$PROFILE" -auto-approve

echo ""
echo "✅ Fast destroy completed"

