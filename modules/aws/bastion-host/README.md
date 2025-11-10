# 堡壘機模組 (Bastion Host Module)

這是一個可重用的Terraform模組，用於部署堡壘機作為跳板伺服器和NAT閘道。

## 🏗️ 架構概述

```
網際網路
    ↑
堡壘機 (公網子網路)
    ↑
私有網路資源 (ECS、RDS等)
```

## ✨ 功能特性

### 🔐 跳板伺服器功能
- **SSH存取控制**：只允許特定IP地址存取
- **金鑰認證**：使用SSH金鑰對進行身份驗證
- **安全群組**：嚴格的網路存取控制
- **監控日誌**：記錄所有存取活動

### 🌐 NAT閘道功能
- **網路位址轉換**：私有網路資源可以透過堡壘機存取網際網路
- **IP轉發**：啟用Linux IP轉發功能
- **iptables規則**：自動設定NAT規則
- **路由表管理**：自動配置私有子網路路由

## 📋 使用方法

### 基本用法

```hcl
module "bastion" {
  source = "../../../modules/aws/bastion-host"

  name                = "bastion-host"
  vpc_id              = data.terraform_remote_state.network.outputs.vpc_id
  subnet_id           = data.terraform_remote_state.network.outputs.public_subnet_ids[0]
  allowed_cidr_blocks = ["YOUR_IP/32"]
  ssh_public_key      = var.ssh_public_key

  tags = {
    Environment = "staging"
    Purpose     = "jump-server"
  }
}
```

### 啟用NAT功能

```hcl
module "bastion" {
  source = "../../../modules/aws/bastion-host"

  name                = "bastion-host"
  vpc_id              = data.terraform_remote_state.network.outputs.vpc_id
  subnet_id           = data.terraform_remote_state.network.outputs.public_subnet_ids[0]
  private_subnet_ids  = data.terraform_remote_state.network.outputs.private_subnet_ids
  internet_gateway_id = data.terraform_remote_state.network.outputs.internet_gateway_id
  allowed_cidr_blocks = ["YOUR_IP/32"]
  ssh_public_key      = var.ssh_public_key
  enable_nat          = true

  tags = {
    Environment = "staging"
    Purpose     = "jump-server-and-nat"
  }
}
```

### 完整配置範例

```hcl
module "bastion" {
  source = "../../../modules/aws/bastion-host"

  # 基本設定
  name                = "bastion-host"
  vpc_id              = data.terraform_remote_state.network.outputs.vpc_id
  subnet_id           = data.terraform_remote_state.network.outputs.public_subnet_ids[0]
  private_subnet_ids  = data.terraform_remote_state.network.outputs.private_subnet_ids
  internet_gateway_id = data.terraform_remote_state.network.outputs.internet_gateway_id
  
  # 安全設定
  allowed_cidr_blocks = ["YOUR_OFFICE_IP/32", "YOUR_HOME_IP/32"]
  ssh_public_key      = var.ssh_public_key
  
  # 實例設定
  instance_type       = "t4g.nano"
  volume_size         = 30
  monitoring          = true
  
  # NAT功能
  enable_nat          = true
  
  # DNS設定
  create_dns_record   = true
  route53_zone_id     = data.terraform_remote_state.network.outputs.hosted_zone_id
  dns_name            = "bastion.staging.moonlit-tech.com"
  dns_ttl             = "300"

  tags = {
    Environment = "staging"
    Purpose     = "jump-server-and-nat"
    ManagedBy   = "terraform"
  }
}
```

## 📝 變數說明

### 必要變數

| 變數名稱 | 描述 | 類型 | 預設值 |
|---------|------|------|--------|
| `name` | 堡壘機名稱 | `string` | - |
| `vpc_id` | VPC ID | `string` | - |
| `subnet_id` | 公網子網路ID | `string` | - |
| `ssh_public_key` | SSH公鑰 | `string` | - |

### 可選變數

| 變數名稱 | 描述 | 類型 | 預設值 |
|---------|------|------|--------|
| `private_subnet_ids` | 私有子網路ID清單（NAT用） | `list(string)` | `[]` |
| `internet_gateway_id` | 網際網路閘道ID（由網路模組提供） | `string` | `""` |
| `allowed_cidr_blocks` | 允許存取的CIDR區塊 | `list(string)` | `["0.0.0.0/0"]` |
| `instance_type` | 實例類型 | `string` | `"t3.micro"` |
| `volume_size` | 根磁碟區大小（GB） | `number` | `30` |
| `monitoring` | 是否啟用詳細監控 | `bool` | `true` |
| `enable_nat` | 是否啟用NAT功能 | `bool` | `false` |
| `create_dns_record` | 是否建立DNS記錄 | `bool` | `false` |
| `route53_zone_id` | Route53區域ID | `string` | `""` |
| `dns_name` | DNS記錄名稱 | `string` | `""` |
| `dns_ttl` | DNS記錄TTL | `string` | `"300"` |
| `tags` | 資源標籤 | `map(string)` | `{}` |

## 📤 輸出說明

| 輸出名稱 | 描述 | 類型 |
|---------|------|------|
| `bastion_instance_id` | 堡壘機實例ID | `string` |
| `bastion_public_ip` | 堡壘機公網IP | `string` |
| `bastion_private_ip` | 堡壘機私有IP | `string` |
| `bastion_dns_name` | 堡壘機DNS名稱 | `string` |
| `bastion_security_group_id` | 堡壘機安全群組ID | `string` |
| `ssh_connection_command` | SSH連線指令範例 | `string` |
| `nat_route_table_id` | NAT路由表ID（如果啟用） | `string` |
| `nat_enabled` | NAT功能是否已啟用 | `bool` |
| `nat_private_subnets` | 使用NAT路由的私有子網路清單 | `list(string)` |

## 🔧 NAT功能詳解

### 網路架構

當啟用NAT功能時，模組會：

1. **使用外部網際網路閘道**：由網路模組提供的網際網路閘道
2. **建立NAT路由表**：將私有子網路的流量路由到堡壘機
3. **配置堡壘機**：
   - 啟用IP轉發：`net.ipv4.ip_forward=1`
   - 設定iptables NAT規則：`iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE`
   - 禁用來源/目標檢查：`source_dest_check = false`

### 相依性

- **網際網路閘道**：必須由網路模組提供
- **VPC和子網路**：必須已存在
- **Route53區域**：如果啟用DNS記錄則需要

### 使用場景

#### 1. ECS服務存取網際網路
```bash
# ECS任務可以透過堡壘機存取外部API
# 例如：下載套件、存取外部服務等
```

#### 2. 私有RDS存取外部資源
```bash
# 資料庫可以存取外部更新伺服器
# 例如：PostgreSQL擴展更新
```

#### 3. 私有實例存取網際網路
```bash
# 私有子網路中的EC2實例可以存取網際網路
# 例如：yum更新、套件安裝等
```

## 🔒 安全考量

### 網路安全
- **網路隔離**：私有資源不直接暴露於網際網路
- **流量監控**：所有外部流量都經過堡壘機
- **存取控制**：可以透過安全群組控制存取

### SSH安全
- 禁用root登入
- 禁用密碼認證
- 僅允許金鑰認證
- 啟用連線保活
- 限制最大會話數

### NAT安全
- **來源NAT**：所有私有資源的流量都會顯示為堡壘機的IP
- **流量記錄**：可以透過堡壘機日誌監控所有外部流量
- **存取控制**：可以透過iptables規則進一步限制存取

## 📊 監控和維護

### 系統監控
堡壘機自動運行監控腳本，每5分鐘記錄：
- CPU使用率
- 記憶體使用率
- 磁碟使用率
- SSH服務狀態
- 網路連線狀態
- NAT功能狀態

### NAT功能監控
```bash
# 檢查NAT規則
sudo iptables -t nat -L POSTROUTING

# 檢查IP轉發狀態
cat /proc/sys/net/ipv4/ip_forward

# 檢查路由表
ip route show
```

## 🛠️ 故障排除

### 常見問題

#### 1. NAT功能不工作
```bash
# 檢查IP轉發
cat /proc/sys/net/ipv4/ip_forward

# 檢查iptables規則
sudo iptables -t nat -L POSTROUTING

# 重新設定NAT規則
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
```

#### 2. 私有資源無法存取網際網路
```bash
# 檢查路由表
ip route show

# 檢查安全群組規則
aws ec2 describe-security-groups --group-ids sg-xxxxxxxxx

# 測試網路連線
ping 8.8.8.8
```

#### 3. SSH連線問題
```bash
# 檢查SSH服務狀態
sudo systemctl status sshd

# 檢查SSH配置
sudo cat /etc/ssh/sshd_config.d/bastion.conf

# 查看SSH日誌
sudo tail -f /var/log/secure
```

## 📈 效能考量

### NAT效能影響
- **網路延遲**：增加約1-2ms的網路延遲
- **頻寬限制**：受堡壘機實例類型限制
- **CPU使用率**：NAT轉換會增加少量CPU使用率

### 建議配置
- **小型環境**：t3.micro（2 vCPU, 1 GB RAM）
- **中型環境**：t3.small（2 vCPU, 2 GB RAM）
- **大型環境**：t3.medium（2 vCPU, 4 GB RAM）

## 🔄 更新維護

```bash
# 更新系統套件
sudo yum update -y

# 重新啟動SSH服務
sudo systemctl restart sshd

# 重新載入iptables規則
sudo iptables-restore < /etc/sysconfig/iptables
```

## 📚 相關資源

- [AWS NAT Gateway 文件](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html)
- [Linux IP Forwarding](https://www.kernel.org/doc/html/latest/networking/ip-sysctl.html)
- [iptables NAT 文件](https://netfilter.org/documentation/HOWTO/NAT-HOWTO.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs) 
