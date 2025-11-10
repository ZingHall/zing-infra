#!/bin/bash

# 堡壘機初始化腳本
# 設定主機名稱
hostname="${hostname}"

# 更新系統
yum update -y

# 安裝必要套件
yum install -y \
  htop \
  vim \
  wget \
  curl \
  unzip \
  jq \
  postgresql15 \
  net-tools \
  iptables-services \
  amazon-ssm-agent

# 設定主機名稱
hostnamectl set-hostname $hostname

# 啟動並啟用 SSM Agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# 安裝 fck-nat
echo "正在安裝 fck-nat..."
cd /tmp
curl -L -o fck-nat.zip https://github.com/AndrewGuenther/fck-nat/releases/latest/download/fck-nat.zip
unzip fck-nat.zip
chmod +x fck-nat

# 移動 fck-nat 到系統路徑
mv fck-nat /usr/local/bin/

# 建立 fck-nat 服務
cat > /etc/systemd/system/fck-nat.service << 'FCKNAT_SERVICE_EOF'
[Unit]
Description=fck-nat NAT Gateway
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/fck-nat
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
FCKNAT_SERVICE_EOF

# 啟用並啟動 fck-nat 服務
systemctl daemon-reload
systemctl enable fck-nat
systemctl start fck-nat

# 建立監控腳本
cat > /usr/local/bin/bastion-monitor.sh << 'MONITOR_SCRIPT_EOF'
#!/bin/bash
LOG_FILE="/var/log/bastion-monitor.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$DATE] 堡壘機狀態檢查開始" >> $LOG_FILE

# 檢查系統資源
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.2f", $3/$2 * 100.0}')
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')

echo "[$DATE] CPU使用率: $CPU_USAGE%" >> $LOG_FILE
echo "[$DATE] 記憶體使用率: $MEMORY_USAGE%" >> $LOG_FILE
echo "[$DATE] 磁碟使用率: $DISK_USAGE%" >> $LOG_FILE

# 檢查SSH服務狀態
if systemctl is-active --quiet sshd; then
    echo "[$DATE] SSH服務: 運行中" >> $LOG_FILE
else
    echo "[$DATE] SSH服務: 已停止" >> $LOG_FILE
fi

# 檢查SSM Agent狀態
if systemctl is-active --quiet amazon-ssm-agent; then
    echo "[$DATE] SSM Agent: 運行中" >> $LOG_FILE
else
    echo "[$DATE] SSM Agent: 已停止" >> $LOG_FILE
fi

# 檢查fck-nat服務狀態
if systemctl is-active --quiet fck-nat; then
    echo "[$DATE] fck-nat服務: 運行中" >> $LOG_FILE
else
    echo "[$DATE] fck-nat服務: 已停止" >> $LOG_FILE
fi

# 檢查網路連線
if ping -c 1 8.8.8.8 > /dev/null 2>&1; then
    echo "[$DATE] 網路連線: 正常" >> $LOG_FILE
else
    echo "[$DATE] 網路連線: 異常" >> $LOG_FILE
fi

# 檢查NAT功能
if [ "${enable_nat}" = "true" ]; then
    if systemctl is-active --quiet fck-nat; then
        echo "[$DATE] NAT功能: fck-nat已啟用" >> $LOG_FILE
    else
        echo "[$DATE] NAT功能: fck-nat未啟用" >> $LOG_FILE
    fi
fi

echo "[$DATE] 堡壘機狀態檢查完成" >> $LOG_FILE
echo "----------------------------------------" >> $LOG_FILE
MONITOR_SCRIPT_EOF

chmod +x /usr/local/bin/bastion-monitor.sh

# 設定監控排程
echo "*/5 * * * * /usr/local/bin/bastion-monitor.sh" | crontab -

# 建立日誌輪轉配置
cat > /etc/logrotate.d/bastion-monitor << 'LOGROTATE_EOF'
/var/log/bastion-monitor.log {
    daily
    missingok
    rotate 7
    compress
    notifempty
    create 644 root root
}
LOGROTATE_EOF

# 設定SSH配置
cat > /etc/ssh/sshd_config.d/bastion.conf << 'SSH_CONFIG_EOF'
# 堡壘機SSH配置
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
MaxSessions 10
ClientAliveInterval 60
ClientAliveCountMax 3
AllowTcpForwarding yes
GatewayPorts yes
X11Forwarding no
SSH_CONFIG_EOF

# 重新啟動SSH服務
systemctl restart sshd

# 建立初始化完成標記
echo "堡壘機初始化完成於 $(date)" > /var/log/bastion-init.log

# 執行首次監控檢查
/usr/local/bin/bastion-monitor.sh

echo "堡壘機設定完成！fck-nat 和 SSM Agent 已啟動" 
