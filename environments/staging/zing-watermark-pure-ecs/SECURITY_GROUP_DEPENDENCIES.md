# Security Group Dependencies and Deletion Issues

## 为什么 Security Groups 难以删除？

### 依赖关系链

```
aws_security_group.ecs_watermark
    ↓ (被引用)
aws_ecs_service.watermark
    ↓ (创建)
ECS Tasks (Fargate)
    ↓ (创建)
ENI (Elastic Network Interface)
    ↓ (附加到)
aws_security_group.ecs_watermark
```

### 问题原因

1. **ECS Service 引用 Security Group**
   ```hcl
   resource "aws_ecs_service" "watermark" {
     network_configuration {
       security_groups = [aws_security_group.ecs_watermark.id]  # ← 引用
     }
   }
   ```

2. **ECS Tasks 创建 ENI**
   - 每个 Fargate 任务都会创建一个 ENI
   - ENI 会附加到指定的 security group
   - 只要任务在运行，ENI 就存在

3. **AWS 阻止删除**
   - AWS 不允许删除正在被 ENI 使用的 security group
   - 必须先删除所有使用该 security group 的 ENI
   - ENI 由 ECS 任务创建，所以必须先停止任务

### 删除顺序（必须按此顺序）

```
1. 停止 ECS Service (desired_count = 0)
   ↓
2. 等待所有任务停止 (ENI 被释放)
   ↓
3. 删除 ECS Service
   ↓
4. 删除 Security Group
```

## 当前依赖关系

### 直接依赖

```hcl
# service.tf
resource "aws_ecs_service" "watermark" {
  network_configuration {
    security_groups = [aws_security_group.ecs_watermark.id]  # ← 直接依赖
  }
}
```

### 隐式依赖（运行时）

- ECS Tasks → ENI → Security Group
- 这些依赖在运行时创建，Terraform 无法直接看到

## 解决方案

### 方案 1: 正确的删除顺序（推荐）

使用 Terraform 时，正确的顺序是：

```bash
# 1. 先设置 desired_count = 0（停止所有任务）
terraform apply -var="desired_count=0"

# 2. 等待任务停止（检查 ENI）
aws ec2 describe-network-interfaces \
  --filters "Name=group-id,Values=<security-group-id>" \
  --region ap-northeast-1 \
  --profile zing-staging

# 3. 删除资源（Terraform 会自动处理顺序）
terraform destroy
```

### 方案 2: 使用 Terraform 的 `depends_on`

虽然 Terraform 会自动处理显式依赖，但可以明确指定：

```hcl
resource "aws_security_group" "ecs_watermark" {
  # ... configuration ...
  
  # 添加 lifecycle 规则，确保在删除前先删除依赖
  lifecycle {
    create_before_destroy = false
  }
}

resource "aws_ecs_service" "watermark" {
  # ... configuration ...
  
  # 明确指定依赖
  depends_on = [
    aws_security_group.ecs_watermark  # 虽然被引用，但这是反向依赖
  ]
  
  # 添加 lifecycle 规则
  lifecycle {
    create_before_destroy = true
  }
}
```

### 方案 3: 手动清理（如果 Terraform 失败）

如果 Terraform destroy 失败，可以手动清理：

```bash
# 1. 停止 ECS Service
aws ecs update-service \
  --cluster zing-watermark-pure-ecs \
  --service zing-watermark \
  --desired-count 0 \
  --region ap-northeast-1 \
  --profile zing-staging

# 2. 等待任务停止（检查状态）
aws ecs describe-services \
  --cluster zing-watermark-pure-ecs \
  --services zing-watermark \
  --region ap-northeast-1 \
  --profile zing-staging

# 3. 删除 ECS Service
aws ecs delete-service \
  --cluster zing-watermark-pure-ecs \
  --service zing-watermark \
  --force \
  --region ap-northeast-1 \
  --profile zing-staging

# 4. 等待 ENI 释放（可能需要几分钟）
aws ec2 describe-network-interfaces \
  --filters "Name=group-id,Values=<security-group-id>" \
  --region ap-northeast-1 \
  --profile zing-staging

# 5. 删除 Security Group
aws ec2 delete-security-group \
  --group-id <security-group-id> \
  --region ap-northeast-1 \
  --profile zing-staging
```

### 方案 4: 使用 Terraform 的 `replace_triggered_by`

可以添加触发器，确保在 security group 变化时重新创建 service：

```hcl
resource "aws_ecs_service" "watermark" {
  # ... configuration ...
  
  # 如果 security group 变化，触发替换
  replace_triggered_by = [
    aws_security_group.ecs_watermark.id
  ]
}
```

## 最佳实践

### 1. 使用 `lifecycle` 规则

```hcl
resource "aws_security_group" "ecs_watermark" {
  # ... configuration ...
  
  lifecycle {
    # 允许 Terraform 在删除前先删除依赖
    create_before_destroy = false
  }
}

resource "aws_ecs_service" "watermark" {
  # ... configuration ...
  
  lifecycle {
    # 创建新服务前先创建新的
    create_before_destroy = true
    # 忽略 task_definition 变化（由 CI/CD 管理）
    ignore_changes = [task_definition]
  }
}
```

### 2. 添加显式依赖

```hcl
resource "aws_ecs_service" "watermark" {
  # ... configuration ...
  
  # 明确指定依赖顺序
  depends_on = [
    aws_lb_listener.watermark,  # 确保 listener 先创建
    aws_security_group.ecs_watermark  # 确保 security group 先创建
  ]
}
```

### 3. 使用变量控制 desired_count

```hcl
variable "desired_count" {
  description = "Number of ECS tasks to run"
  type        = number
  default     = 2
}

resource "aws_ecs_service" "watermark" {
  desired_count = var.desired_count
  # ... rest of configuration ...
}
```

这样可以在删除前先设置为 0：

```bash
terraform apply -var="desired_count=0"
# 等待任务停止
terraform destroy
```

## 常见错误

### 错误 1: DependencyViolation

```
Error: deleting Security Group: DependencyViolation: 
resource sg-xxx has a dependent object
```

**原因**: ENI 仍在使用 security group

**解决**: 先停止 ECS 服务，等待 ENI 释放

### 错误 2: InvalidParameterValue

```
Error: InvalidParameterValue: 
The security group 'sg-xxx' does not exist
```

**原因**: 尝试在 security group 删除后使用它

**解决**: 确保删除顺序正确

## 总结

Security groups 难以删除的主要原因是：

1. ✅ **ECS Service 直接引用** security group
2. ✅ **ECS Tasks 创建 ENI**，ENI 附加到 security group
3. ✅ **AWS 阻止删除**正在被使用的 security group

**解决方案**：
- 先停止 ECS Service (`desired_count = 0`)
- 等待任务停止和 ENI 释放
- 然后删除 security group

**Terraform 会自动处理顺序**，但有时需要手动干预（特别是如果资源在 Terraform 外被修改）。

