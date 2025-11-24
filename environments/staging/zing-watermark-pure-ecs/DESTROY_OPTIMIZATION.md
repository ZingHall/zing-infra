# Destroy 優化指南

## 導致 Destroy 緩慢的主要原因

### 1. **ECS Service 停止任務緩慢** ⏱️ (最常見)
- ECS Service 需要等待所有任務優雅關閉
- `health_check_grace_period_seconds = 60` 會延遲停止
- `deployment_minimum_healthy_percent = 100` 要求保持健康任務

### 2. **ECR Repository 刪除緩慢** 🐌
- `force_delete = false` 時，需要手動刪除所有圖片
- 如果有大量圖片版本，刪除會很慢

### 3. **CloudWatch Log Groups** 📊
- 如果有大量日誌數據，刪除可能很慢
- 默認保留策略可能保留大量日誌

## 優化方案

### 方案 1: 手動停止 ECS Service（推薦）

在運行 `terraform destroy` 之前，先手動停止 ECS Service：

```bash
# 設置 desired_count 為 0，強制停止所有任務
aws ecs update-service \
  --cluster zing-watermark-pure-ecs \
  --service zing-watermark \
  --desired-count 0 \
  --force-new-deployment \
  --profile zing-staging \
  --region ap-northeast-1

# 等待服務停止（通常需要 1-2 分鐘）
aws ecs wait services-stable \
  --cluster zing-watermark-pure-ecs \
  --services zing-watermark \
  --profile zing-staging \
  --region ap-northeast-1

# 然後運行 terraform destroy
terraform destroy -var="aws_profile=zing-staging"
```

### 方案 2: 修改 Terraform 配置以加速 Destroy

#### 2.1 添加 ECS Service 的 force_new_deployment

在 `service.tf` 中添加：

```terraform
resource "aws_ecs_service" "watermark" {
  # ... existing configuration ...
  
  # 在 destroy 時快速停止
  deployment_configuration {
    maximum_percent         = 200
    minimum_healthy_percent = 0  # 允許 0% 健康，加速停止
  }
  
  # 減少健康檢查寬限期
  health_check_grace_period_seconds = 10  # 從 60 減少到 10
}
```

#### 2.2 啟用 ECR force_delete（僅用於 staging）

在 `service.tf` 中修改：

```terraform
module "ecr" {
  source = "../../../modules/aws/ecr"

  name                 = "zing-watermark"
  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true
  count_number         = 10
  force_delete         = true  # 改為 true，允許自動刪除所有圖片
}
```

#### 2.3 添加 CloudWatch Log Group 的 retention

在 `ecs-role` 模組調用時指定較短的保留期：

```terraform
module "ecs_role" {
  # ... existing configuration ...
  
  log_retention_in_days = 7  # 只保留 7 天日誌，減少刪除時間
}
```

### 方案 3: 創建快速 Destroy 腳本

創建 `fast-destroy.sh`：

```bash
#!/bin/bash
set -e

PROFILE="${1:-zing-staging}"
REGION="ap-northeast-1"
CLUSTER="zing-watermark-pure-ecs"
SERVICE="zing-watermark"

echo "🚀 Fast destroy: Stopping ECS service first..."

# 1. 停止 ECS Service
aws ecs update-service \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --desired-count 0 \
  --force-new-deployment \
  --profile "$PROFILE" \
  --region "$REGION" > /dev/null

echo "⏳ Waiting for service to stop..."
aws ecs wait services-stable \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --profile "$PROFILE" \
  --region "$REGION" || true

# 2. 刪除所有運行中的任務（強制）
echo "🗑️  Stopping all running tasks..."
TASK_ARNS=$(aws ecs list-tasks \
  --cluster "$CLUSTER" \
  --service-name "$SERVICE" \
  --profile "$PROFILE" \
  --region "$REGION" \
  --query 'taskArns[]' \
  --output text)

if [ -n "$TASK_ARNS" ]; then
  for TASK_ARN in $TASK_ARNS; do
    aws ecs stop-task \
      --cluster "$CLUSTER" \
      --task "$TASK_ARN" \
      --profile "$PROFILE" \
      --region "$REGION" > /dev/null
  done
  echo "✅ All tasks stopped"
fi

# 3. 等待任務完全停止
echo "⏳ Waiting for tasks to stop..."
sleep 10

# 4. 運行 Terraform destroy
echo "🗑️  Running Terraform destroy..."
terraform destroy -var="aws_profile=$PROFILE" -auto-approve

echo "✅ Fast destroy completed"
```

## 預期時間改善

| 操作 | 原始時間 | 優化後時間 |
|------|---------|-----------|
| ECS Service 停止 | 2-5 分鐘 | 30-60 秒 |
| ECR 刪除 | 1-3 分鐘 | 10-30 秒 |
| CloudWatch Logs | 30-60 秒 | 10-20 秒 |
| **總計** | **4-9 分鐘** | **1-2 分鐘** |

## 注意事項

⚠️ **重要**：
- `force_delete = true` 會自動刪除所有 ECR 圖片，請確保 staging 環境可以接受
- 減少 `health_check_grace_period_seconds` 可能導致不健康的任務被快速終止
- 手動停止服務後，Terraform destroy 會更快，因為不需要等待任務停止

## 推薦工作流程

1. **開發環境**: 使用 `force_delete = true` 和較短的健康檢查寬限期
2. **Staging 環境**: 使用快速 destroy 腳本
3. **Production 環境**: 保持默認配置，確保優雅關閉

