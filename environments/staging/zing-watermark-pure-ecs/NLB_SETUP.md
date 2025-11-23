# NLB Setup for Watermark Service

## 概述

已为 `zing-watermark` 服务配置了 Network Load Balancer (NLB)，支持：
- ✅ **Scale Out**：多个 ECS 任务实例
- ✅ **负载均衡**：自动分发流量
- ✅ **端到端 mTLS**：NLB 使用 TCP passthrough，保持 mTLS 完整
- ✅ **高可用**：跨多个可用区

## 架构

```
TEE (Client) ──mTLS──> NLB (TCP Passthrough) ──mTLS──> ECS Tasks
                                              ├── Task 1 (10.0.1.10:8080)
                                              ├── Task 2 (10.0.1.11:8080)
                                              └── Task 3 (10.0.1.12:8080)
```

## 配置详情

### NLB 配置

- **类型**：内部 NLB（只在 VPC 内可访问）
- **协议**：TCP（passthrough，保持 mTLS）
- **端口**：8080
- **跨可用区负载均衡**：已启用

### Target Group 配置

- **协议**：TCP
- **端口**：8080
- **目标类型**：IP（Fargate）
- **健康检查**：TCP（端口 8080）
- **注销延迟**：30 秒

### ECS Service 配置

- **Desired Count**：2（可调整）
- **连接到 NLB**：已配置
- **安全组**：允许 NLB 和 TEE 访问

## 部署步骤

### 1. 应用 Terraform 配置

```bash
cd zing-infra/environments/staging/zing-watermark-pure-ecs
terraform init
terraform plan
terraform apply
```

### 2. 获取 NLB DNS 名称

```bash
# 从 Terraform outputs
terraform output nlb_dns_name

# 或从 AWS Console
aws elbv2 describe-load-balancers \
  --names zing-watermark-nlb \
  --region ap-northeast-1 \
  --profile zing-staging \
  --query 'LoadBalancers[0].DNSName' \
  --output text
```

### 3. 配置 TEE 连接到 NLB

#### 选项 A: 使用 NLB DNS 名称（推荐）

在 `nautilus-watermark-service/src/nautilus-server/src/apps/zing-watermark/allowed_endpoints.yaml` 中添加：

```yaml
endpoints:
  - fullnode.testnet.sui.io
  - api.weatherapi.com
  - seal-key-server-testnet-1.mystenlabs.com
  - seal-key-server-testnet-2.mystenlabs.com
  - <nlb-dns-name>.elb.ap-northeast-1.amazonaws.com  # NLB DNS 名称
```

#### 选项 B: 使用环境变量

在 TEE 配置中设置：

```bash
export ECS_WATERMARK_ENDPOINT="https://<nlb-dns-name>.elb.ap-northeast-1.amazonaws.com:8080"
```

### 4. 更新 TEE 代码使用 mTLS 客户端

确保 TEE 代码使用 `create_mtls_client()` 连接到 ECS：

```rust
use nautilus_server::mtls_client::create_mtls_client;

let client = create_mtls_client()?;
let ecs_endpoint = std::env::var("ECS_WATERMARK_ENDPOINT")
    .unwrap_or_else(|_| "https://<nlb-dns-name>.elb.ap-northeast-1.amazonaws.com:8080".to_string());

let response = client
    .get(format!("{}/health", ecs_endpoint))
    .send()
    .await?;
```

## 验证

### 1. 检查 NLB 状态

```bash
aws elbv2 describe-load-balancers \
  --names zing-watermark-nlb \
  --region ap-northeast-1 \
  --profile zing-staging
```

### 2. 检查 Target Group 健康状态

```bash
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn> \
  --region ap-northeast-1 \
  --profile zing-staging
```

### 3. 检查 ECS 任务

```bash
aws ecs list-tasks \
  --cluster zing-watermark-pure-ecs \
  --service-name zing-watermark \
  --region ap-northeast-1 \
  --profile zing-staging
```

### 4. 测试连接（从 TEE 或 EC2）

```bash
# 使用 curl 测试（需要客户端证书）
curl --cert client.crt --key client.key --cacert ca.crt \
  https://<nlb-dns-name>.elb.ap-northeast-1.amazonaws.com:8080/health
```

## Scale Out

### 增加任务数量

```bash
# 方法 1: 更新 Terraform
# 在 service.tf 中修改 desired_count
desired_count = 3  # 增加到 3 个任务

terraform apply

# 方法 2: 使用 AWS CLI
aws ecs update-service \
  --cluster zing-watermark-pure-ecs \
  --service zing-watermark \
  --desired-count 3 \
  --region ap-northeast-1 \
  --profile zing-staging
```

### 自动扩展（可选）

可以配置 ECS Service Auto Scaling：

```hcl
resource "aws_appautoscaling_target" "watermark" {
  max_capacity       = 10
  min_capacity       = 2
  resource_id        = "service/${module.ecs_cluster.cluster_name}/${aws_ecs_service.watermark.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "watermark" {
  name               = "zing-watermark-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.watermark.resource_id
  scalable_dimension = aws_appautoscaling_target.watermark.scalable_dimension
  service_namespace  = aws_appautoscaling_target.watermark.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0
  }
}
```

## 安全注意事项

1. **NLB 是内部的**：只在 VPC 内可访问，不暴露到公网
2. **安全组限制**：只允许 TEE VPC (10.0.0.0/16) 访问
3. **mTLS 加密**：端到端 mTLS，NLB 不终止 TLS
4. **证书验证**：TEE 和 ECS 都验证对方证书

## 故障排除

### NLB 无法连接

1. 检查安全组规则（允许 TEE VPC 访问）
2. 检查 Target Group 健康状态
3. 检查 ECS 任务是否运行

### 健康检查失败

1. 检查 ECS 任务日志
2. 验证端口 8080 是否监听
3. 检查安全组（允许 NLB 访问 ECS）

### mTLS 连接失败

1. 验证证书配置
2. 检查 TEE 客户端证书
3. 验证 ECS 服务器证书
4. 检查证书是否过期

## Outputs

Terraform 输出以下信息：

- `nlb_dns_name`: NLB DNS 名称
- `nlb_arn`: NLB ARN
- `nlb_zone_id`: NLB Zone ID
- `target_group_arn`: Target Group ARN
- `nlb_security_group_id`: NLB Security Group ID

## 下一步

1. ✅ NLB 已配置
2. ⏳ 更新 TEE `allowed_endpoints.yaml` 添加 NLB DNS
3. ⏳ 更新 TEE 代码使用 NLB 端点
4. ⏳ 测试连接
5. ⏳ 根据需要调整 `desired_count`

