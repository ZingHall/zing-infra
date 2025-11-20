# 重新部署正常配置

## ✅ 已恢復的配置

所有臨時調試配置已恢復為正常配置：

1. **Subnet**: `public_subnet_ids` → `private_subnet_ids`
2. **Public IP**: `enable_public_ip = true` → `enable_public_ip = false`
3. **健康檢查寬限期**: `600` → `300` (5分鐘)
4. **不健康閾值**: `10` → `3`
5. **臨時安全組規則**: 已移除
   - `enclave_ssh_internet` (SSH 從互聯網)
   - `enclave_direct_http` (HTTP 從互聯網)

## 部署步驟

### 1. 檢查 Terraform 計劃

```bash
cd zing-infra/environments/staging/nautilus-enclave

# 初始化（如果需要）
terraform init -reconfigure \
  -backend-config="bucket=terraform-zing-staging" \
  -backend-config="key=nautilus-enclave.tfstate" \
  -backend-config="region=ap-northeast-1" \
  -backend-config="encrypt=true" \
  -backend-config="dynamodb_table=terraform-lock-table"

# 查看計劃
terraform plan
```

### 2. 應用更改

```bash
# 應用配置更改（這會更新 Launch Template 和配置，但不會自動替換實例）
terraform apply

# 這會：
# - 更新 Launch Template（包含新的 user-data.sh）
# - 更新 ASG 配置（subnet, health check 等）
# - 移除臨時安全組規則
# - 恢復健康檢查配置
```

**注意**：`terraform apply` 不會自動替換實例。需要手動觸發實例替換（見步驟 3）。

### 3. 觸發實例替換

應用 Terraform 更改後，需要手動觸發實例替換以應用新的配置：

**方法 A: 通過 AWS Console**
1. 進入 **Auto Scaling Groups**
2. 選擇 `nautilus-watermark-staging-enclave-asg`
3. 點擊 **Edit**
4. 在 **Launch template** 部分，確認使用 **Latest** 版本
5. 保存更改
6. 手動終止現有實例，ASG 會自動啟動新實例

**方法 B: 通過 AWS CLI**
```bash
# 獲取實例 ID
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names nautilus-watermark-staging-enclave-asg \
  --region ap-northeast-1 \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text)

# 終止實例（ASG 會自動啟動新實例，使用新的 Launch Template）
aws autoscaling terminate-instance-in-auto-scaling-group \
  --instance-id $INSTANCE_ID \
  --should-decrement-desired-capacity \
  --region ap-northeast-1
```

### 4. 等待實例啟動

新實例啟動需要時間：
- 實例啟動: ~2-3 分鐘
- user-data 執行: ~5-10 分鐘（包括編譯 socat）
- Enclave 啟動: ~1-2 分鐘
- 總計: ~10-15 分鐘

### 4. 驗證部署

#### 4.1 檢查實例狀態

```bash
# 獲取實例 ID
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names nautilus-watermark-staging-enclave-asg \
  --region ap-northeast-1 \
  --query 'AutoScalingGroups[0].Instances[*].InstanceId' \
  --output text

# 檢查實例狀態
aws ec2 describe-instances \
  --instance-ids <INSTANCE_ID> \
  --region ap-northeast-1 \
  --query 'Reservations[0].Instances[0].{State:State.Name,PrivateIP:PrivateIpAddress,PublicIP:PublicIpAddress}' \
  --output table
```

#### 4.2 檢查 ALB 目標健康

```bash
# 獲取 target group ARN
TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
  --region ap-northeast-1 \
  --query 'TargetGroups[?contains(TargetGroupName, `enclave`)].TargetGroupArn' \
  --output text)

# 檢查目標健康狀態
aws elbv2 describe-target-health \
  --target-group-arn "$TARGET_GROUP_ARN" \
  --region ap-northeast-1 \
  --query 'TargetHealthDescriptions[*].{Instance:Target.Id,Port:Target.Port,Health:TargetHealth.State,Reason:TargetHealth.Reason}' \
  --output table
```

#### 4.3 測試健康檢查端點

```bash
# 通過 ALB 域名測試
curl -s https://enclave.staging.zing.you/health_check | jq '.'

# 或通過 ALB DNS 名稱
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --region ap-northeast-1 \
  --query 'LoadBalancers[?contains(LoadBalancerName, `enclave`)].DNSName' \
  --output text)

curl -s "https://$ALB_DNS/health_check" | jq '.'
```

## 預期結果

### 成功標誌

- ✅ 實例在 private subnet 中
- ✅ 實例沒有 public IP
- ✅ ALB 目標健康狀態為 `healthy`
- ✅ 健康檢查端點返回 200 OK
- ✅ 通過 ALB 域名可以訪問

### 如果健康檢查失敗

如果新實例的健康檢查失敗，可能原因：

1. **user-data 執行時間過長**：編譯 socat 需要時間
   - 等待更長時間（最多 15 分鐘）
   - 檢查 CloudWatch 日誌

2. **EIF 文件下載失敗**：檢查 IAM 權限
   - 驗證實例角色有 S3 讀取權限
   - 檢查 user-data 日誌

3. **Enclave 啟動失敗**：檢查日誌
   - `/var/log/enclave-init.log`
   - CloudWatch Logs

## 故障排除

### 檢查實例日誌

```bash
# 通過 Systems Manager Session Manager 或 Bastion Host 連接到實例
# 然後檢查日誌

# user-data 日誌
sudo tail -100 /var/log/enclave-init.log

# cloud-init 日誌
sudo tail -100 /var/log/cloud-init-output.log

# 檢查 enclave 狀態
sudo nitro-cli describe-enclaves

# 檢查 socat
ps aux | grep socat

# 測試本地健康檢查
curl http://localhost:3000/health_check
```

### 檢查 CloudWatch Logs

```bash
# 查看最近的日誌
aws logs tail /aws/ec2/nautilus-watermark-staging --follow --region ap-northeast-1
```

## 完成後

一旦確認一切正常：

1. ✅ 驗證所有組件正常工作
2. ✅ 確認 ALB 健康檢查通過
3. ✅ 測試通過域名訪問
4. ✅ 監控一段時間確保穩定

## 注意事項

- 新實例啟動時會自動執行更新後的 `user-data.sh`，包括編譯 socat
- 編譯 socat 需要 5-10 分鐘，這會增加實例啟動時間
- 確保 EIF 文件在 S3 中可用
- 確保 IAM 角色有正確的權限

