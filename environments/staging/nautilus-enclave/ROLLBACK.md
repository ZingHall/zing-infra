# Enclave 回滚指南

## 概述

Enclave 可以通过以下方式回滚到之前的版本：

1. **通过 Terraform 回滚**（推荐）- 更新 `eif_version` 变量
2. **手动回滚** - 在实例上直接替换 EIF 文件
3. **通过 Auto Scaling Group 实例刷新** - 更新 launch template

## 方法 1: 通过 Terraform 回滚（推荐）

这是最安全和推荐的方法，适用于生产环境。

### 步骤 1: 查找之前的 EIF 版本

```bash
# 列出 S3 中的所有 EIF 文件
aws s3 ls s3://zing-enclave-artifacts-staging/eif/staging/ \
  --profile zing-staging \
  --region ap-northeast-1 | grep "nitro-"

# 输出示例：
# 2025-11-22 12:00:00  150000000  nitro-abc1234.eif
# 2025-11-22 11:00:00  150000000  nitro-def5678.eif
# 2025-11-22 10:00:00  150000000  nitro-c39d8af.eif  <- 当前版本
```

### 步骤 2: 更新 Terraform 变量

```bash
cd zing-infra/environments/staging/nautilus-enclave

# 方法 A: 通过命令行参数
terraform apply -var="eif_version=abc1234" -auto-approve

# 方法 B: 更新 variables.tf 或创建 terraform.tfvars
# 编辑 variables.tf，将 default 改为旧版本
# 或创建 terraform.tfvars:
echo 'eif_version = "abc1234"' > terraform.tfvars
terraform apply -auto-approve
```

### 步骤 3: 触发实例刷新

Terraform 会更新 launch template，但不会自动刷新现有实例。需要手动触发：

```bash
# 获取 Auto Scaling Group 名称
ASG_NAME=$(terraform output -raw autoscaling_group_name)

# 触发实例刷新（零停机时间）
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name "$ASG_NAME" \
  --preferences MinHealthyPercentage=100,InstanceWarmup=300 \
  --profile zing-staging \
  --region ap-northeast-1

# 监控刷新进度
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --profile zing-staging \
  --region ap-northeast-1
```

### 步骤 4: 验证回滚

```bash
# 检查新实例是否使用旧版本 EIF
aws ssm start-session --target <instance-id> --profile zing-staging

# 在实例内检查
ls -lh /opt/nautilus/nitro.eif
sudo nitro-cli describe-enclaves

# 测试健康检查
curl http://localhost:3000/health_check
```

## 方法 2: 手动回滚（快速修复）

适用于紧急情况，需要快速回滚单个实例。

### 步骤 1: 连接到实例

```bash
# 获取实例 ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=nautilus-watermark-staging" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text \
  --profile zing-staging \
  --region ap-northeast-1)

# 通过 SSM 连接
aws ssm start-session --target "$INSTANCE_ID" --profile zing-staging
```

### 步骤 2: 停止当前 Enclave

```bash
# 在实例内执行
sudo nitro-cli terminate-enclave --all
```

### 步骤 3: 下载旧版本 EIF

```bash
# 在实例内执行
OLD_VERSION="abc1234"  # 替换为要回滚的版本
aws s3 cp s3://zing-enclave-artifacts-staging/eif/staging/nitro-${OLD_VERSION}.eif \
  /opt/nautilus/nitro.eif \
  --region ap-northeast-1

# 验证文件
ls -lh /opt/nautilus/nitro.eif
```

### 步骤 4: 启动 Enclave

```bash
# 在实例内执行
sudo nitro-cli run-enclave \
  --cpu-count 2 \
  --memory 512 \
  --eif-path /opt/nautilus/nitro.eif

# 等待启动
sleep 10

# 验证
sudo nitro-cli describe-enclaves

# 重新暴露端口
bash /opt/nautilus/expose_enclave.sh
```

## 方法 3: 通过 Auto Scaling Group 实例刷新

与方法 1 类似，但更细粒度控制。

### 步骤 1: 更新 Launch Template

```bash
cd zing-infra/environments/staging/nautilus-enclave

# 更新 eif_version
terraform apply -var="eif_version=abc1234" -target=module.nautilus_enclave.aws_launch_template.enclave
```

### 步骤 2: 触发实例刷新

```bash
ASG_NAME=$(terraform output -raw autoscaling_group_name)

aws autoscaling start-instance-refresh \
  --auto-scaling-group-name "$ASG_NAME" \
  --preferences \
    MinHealthyPercentage=100,\
    InstanceWarmup=300,\
    CheckpointPercentages=50,100 \
  --profile zing-staging \
  --region ap-northeast-1
```

## 回滚脚本

创建快速回滚脚本：

```bash
#!/bin/bash
# rollback-enclave.sh

set -e

OLD_VERSION="${1:-}"
if [ -z "$OLD_VERSION" ]; then
  echo "Usage: $0 <eif_version>"
  echo "Example: $0 abc1234"
  exit 1
fi

cd "$(dirname "$0")"

echo "🔄 Rolling back enclave to version: $OLD_VERSION"
echo ""

# Update Terraform
echo "📝 Updating Terraform configuration..."
terraform apply -var="eif_version=$OLD_VERSION" -auto-approve

# Get ASG name
ASG_NAME=$(terraform output -raw autoscaling_group_name)
echo "📦 Auto Scaling Group: $ASG_NAME"
echo ""

# Trigger instance refresh
echo "🚀 Triggering instance refresh..."
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name "$ASG_NAME" \
  --preferences MinHealthyPercentage=100,InstanceWarmup=300 \
  --profile zing-staging \
  --region ap-northeast-1

echo ""
echo "✅ Rollback initiated"
echo "Monitor progress with:"
echo "  aws autoscaling describe-instance-refreshes --auto-scaling-group-name $ASG_NAME --profile zing-staging --region ap-northeast-1"
```

## 注意事项

### 1. EIF 文件保留策略

确保旧版本的 EIF 文件仍在 S3 中：

```bash
# 检查 S3 生命周期策略
aws s3api get-bucket-lifecycle-configuration \
  --bucket zing-enclave-artifacts-staging \
  --profile zing-staging
```

### 2. 版本命名

EIF 文件按 commit SHA 命名：
- 格式：`nitro-{commit_short_sha}.eif`
- 示例：`nitro-abc1234.eif`

### 3. 零停机时间

使用 Auto Scaling Group 实例刷新可以实现零停机时间回滚：
- `MinHealthyPercentage=100` 确保至少 1 个实例健康
- 新实例启动并健康后，旧实例才会终止

### 4. 验证回滚

回滚后验证：
1. Enclave 健康检查通过
2. 应用程序功能正常
3. 日志中没有错误

## 故障排除

### 问题：旧版本 EIF 文件不存在

```bash
# 检查 S3
aws s3 ls s3://zing-enclave-artifacts-staging/eif/staging/ \
  --profile zing-staging

# 如果文件不存在，需要：
# 1. 从备份恢复
# 2. 或重新构建该版本的 EIF
```

### 问题：实例刷新卡住

```bash
# 检查刷新状态
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name "$ASG_NAME" \
  --profile zing-staging

# 取消刷新（如果需要）
aws autoscaling cancel-instance-refresh \
  --auto-scaling-group-name "$ASG_NAME" \
  --profile zing-staging
```

### 问题：回滚后 Enclave 无法启动

1. 检查 CloudWatch 日志
2. 验证 EIF 文件完整性
3. 检查实例资源（CPU/内存）
4. 查看 `/var/log/nitro_enclaves/` 错误日志

## 最佳实践

1. **保留多个版本**：在 S3 中保留最近 5-10 个版本的 EIF 文件
2. **测试回滚流程**：定期测试回滚流程，确保在紧急情况下可以快速执行
3. **文档化版本**：记录每个版本的变更和已知问题
4. **监控部署**：部署后密切监控，及时发现问题并回滚

