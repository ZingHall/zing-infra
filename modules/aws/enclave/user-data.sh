#!/bin/bash
set +e
exec > >(tee /var/log/enclave-init.log) 2>&1
retry(){ local m=$1;shift;a=1;while [ $a -le $m ];do "$@" && return 0;echo "Retry $a/$m...";sleep 5;a=$((a+1));done;return 1;}

S3_BUCKET="${s3_bucket}"
EIF_VERSION="${eif_version}"
EIF_PATH="${eif_path}"
ENCLAVE_CPU="${enclave_cpu}"
ENCLAVE_MEMORY="${enclave_memory}"
ENCLAVE_PORT="${enclave_port}"
ENCLAVE_INIT_PORT="${enclave_init_port}"
NAME="${name}"
REGION="${region}"
LOG_GROUP_NAME="${log_group_name}"

echo "Init: $NAME"
retry 3 yum update -y || { yum clean all;yum makecache; }
amazon-linux-extras enable aws-nitro-enclaves-cli
retry 3 yum install -y docker jq aws-cli curl wget git amazon-ssm-agent
yum groupinstall -y "Development Tools" 2>/dev/null
yum install -y openssl-devel
retry 3 yum install -y aws-nitro-enclaves-cli aws-nitro-enclaves-cli-devel || exit 1
usermod -aG ne,docker ec2-user

cd /tmp
[ ! -f socat-1.7.4.4.tar.gz ] && retry 3 wget -q http://www.dest-unreach.org/socat/download/socat-1.7.4.4.tar.gz || retry 3 wget -q https://github.com/craigsdennis/socat/archive/refs/tags/v1.7.4.4.tar.gz -O socat-1.7.4.4.tar.gz || touch /tmp/socat-failed
[ ! -f /tmp/socat-failed ] && tar -xzf socat-1.7.4.4.tar.gz && cd socat-1.7.4.4 && (./configure --enable-vsock || ./configure) && make && sudo make install || touch /tmp/socat-failed
[ -f /tmp/socat-failed ] && yum install -y socat

echo 'KERNEL=="vsock",MODE="660",GROUP="ne"' >/etc/udev/rules.d/51-vsock.rules
udevadm control --reload-rules && udevadm trigger
systemctl start amazon-ssm-agent && systemctl enable amazon-ssm-agent
retry 3 yum install -y amazon-cloudwatch-agent
mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
cat >/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<CW
{"logs":{"logs_collected":{"files":{"collect_list":[{"file_path":"/var/log/enclave-init.log","log_group_name":"$LOG_GROUP_NAME","log_stream_name":"{instance_id}/enclave-init.log","retention_in_days":7},{"file_path":"/var/log/messages","log_group_name":"$LOG_GROUP_NAME","log_stream_name":"{instance_id}/messages","retention_in_days":7},{"file_path":"/var/log/secure","log_group_name":"$LOG_GROUP_NAME","log_stream_name":"{instance_id}/secure","retention_in_days":7},{"file_path":"/var/log/cloud-init.log","log_group_name":"$LOG_GROUP_NAME","log_stream_name":"{instance_id}/cloud-init.log","retention_in_days":7},{"file_path":"/var/log/cloud-init-output.log","log_group_name":"$LOG_GROUP_NAME","log_stream_name":"{instance_id}/cloud-init-output.log","retention_in_days":7}]}}}}
CW
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s
systemctl enable amazon-cloudwatch-agent
systemctl start docker && systemctl enable docker
systemctl start nitro-enclaves-allocator && systemctl enable nitro-enclaves-allocator
systemctl restart nitro-enclaves-allocator

ALLOWED_ENDPOINTS=""

# Configure vsock-proxy if endpoints were extracted
if [ -n "$ALLOWED_ENDPOINTS" ]; then
  echo "Configuring vsock-proxy..."
  sudo mkdir -p /etc/nitro_enclaves
  [ -f /etc/nitro_enclaves/vsock-proxy.yaml ] && sudo cp /etc/nitro_enclaves/vsock-proxy.yaml /etc/nitro_enclaves/vsock-proxy.yaml.bak
  
  if command -v python3 >/dev/null 2>&1; then
    python3 << PYTHON_SCRIPT
import re,sys
yaml_file='/etc/nitro_enclaves/vsock-proxy.yaml'
endpoints=set()
try:
    with open(yaml_file,'r') as f:
        c=f.read()
        l=c.split('\n')
    for m in re.finditer(r'-\s*\{address:\s*([^,]+),\s*port:\s*(\d+)\}',c):
        endpoints.add((m.group(1).strip(),m.group(2)))
    i=0
    while i<len(l):
        if l[i].strip().startswith('- address:'):
            h=l[i].split('address:')[1].strip()
            if i+1<len(l) and 'port:' in l[i+1]:
                endpoints.add((h,l[i+1].split('port:')[1].strip()))
                i+=2
                continue
            endpoints.add((h,'443'))
        i+=1
except:pass
for ep in """$ALLOWED_ENDPOINTS""".split():
    if ep:endpoints.add((ep.split(':')[0].strip(),'443'))
try:
    with open(yaml_file,'w') as f:
        f.write('allowlist:\n')
        for h,p in sorted(endpoints):
            f.write(f'  - address: {h}\n    port: {p}\n')
except Exception as e:
    print(f"Error: {e}",file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
    [ $? -eq 0 ] && [ -f /etc/nitro_enclaves/vsock-proxy.yaml ] || echo "Python failed, using bash fallback"
  fi
  
  if [ ! -f /etc/nitro_enclaves/vsock-proxy.yaml ] || ! grep -q "allowlist:" /etc/nitro_enclaves/vsock-proxy.yaml 2>/dev/null; then
    T=$(mktemp)
    echo "allowlist:">"$T"
    [ -f /etc/nitro_enclaves/vsock-proxy.yaml ] && sudo grep -E "^\s*-\s*\{address:" /etc/nitro_enclaves/vsock-proxy.yaml | sed -E 's/.*\{address:\s*([^,]+),\s*port:\s*([0-9]+)\}.*/\1 \2/' | sort -u | while read h p; do [ -n "$h" ] && printf "  - address: %s\n    port: %s\n" "$h" "$${p:-443}">>"$T"; done
    for ep in $ALLOWED_ENDPOINTS; do
      h=$(echo "$ep"|sed 's/:.*$//')
      grep -q "address: $h" "$T" || printf "  - address: %s\n    port: 443\n" "$h">>"$T"
    done
    sudo mv "$T" /etc/nitro_enclaves/vsock-proxy.yaml
  fi
  PORT=8101
  for ep in $ALLOWED_ENDPOINTS; do
    h=$(echo "$ep"|sed 's/:.*$//')
    sudo pkill -f "vsock-proxy $PORT" 2>/dev/null || true
    sleep 1
    sudo vsock-proxy $PORT $h 443 --config /etc/nitro_enclaves/vsock-proxy.yaml &
    PORT=$((PORT+1))
  done
else
  echo "No allowed endpoints configured, skipping vsock-proxy setup"
fi

echo "vsock-proxy configuration completed"
echo "=========================================="

# Create enclave directory
echo "Creating enclave directory..."
mkdir -p /opt/nautilus
cd /opt/nautilus

# Download expose_enclave.sh script from S3 (required, no fallback)
echo "Downloading expose_enclave.sh from S3..."
EXPOSE_SCRIPT_S3="s3://${s3_bucket}/${eif_path}/expose_enclave.sh"
if ! retry 3 aws s3 cp "$EXPOSE_SCRIPT_S3" /opt/nautilus/expose_enclave.sh; then
  echo "❌ Failed to download expose_enclave.sh from S3: $EXPOSE_SCRIPT_S3"
  echo "   Please ensure Terraform has uploaded the script to S3"
  exit 1
fi
chmod +x /opt/nautilus/expose_enclave.sh
echo "✅ Downloaded expose_enclave.sh from S3"

# Download EIF file from S3
echo "Downloading EIF file from S3..."
EIF_S3_PATH="s3://${s3_bucket}/${eif_path}/nitro-${eif_version}.eif"

echo "EIF S3 path: $EIF_S3_PATH"

# Download to temporary location first, then move to final location
# This ensures we don't have a partial/corrupted file in the final location
if retry 3 aws s3 ls "$EIF_S3_PATH" 2>/dev/null; then
  echo "Found EIF file: $EIF_S3_PATH"
  echo "Downloading to temporary location..."
  retry 5 aws s3 cp "$EIF_S3_PATH" /tmp/nitro.eif || {
    echo "❌ Failed to download EIF file after retries"
    exit 1
  }
  
  # Verify file size (should be large, at least 100MB)
  FILE_SIZE=$(stat -f%z /tmp/nitro.eif 2>/dev/null || stat -c%s /tmp/nitro.eif 2>/dev/null || echo "0")
  if [ "$FILE_SIZE" -gt 100000000 ]; then
    echo "File downloaded successfully, size: $FILE_SIZE bytes"
    echo "Moving to final location..."
    sudo mkdir -p /opt/nautilus
    sudo mv /tmp/nitro.eif /opt/nautilus/nitro.eif
    sudo chmod 644 /opt/nautilus/nitro.eif
    echo "EIF file downloaded and verified successfully"
    ls -lh /opt/nautilus/nitro.eif
    
    # Download allowed_endpoints.yaml from S3
    YAML_S3_PATH="s3://${s3_bucket}/${eif_path}/allowed_endpoints-${eif_version}.yaml"
    echo "Downloading allowed_endpoints.yaml from $YAML_S3_PATH..."
    if retry 3 aws s3 cp "$YAML_S3_PATH" /tmp/allowed_endpoints.yaml 2>/dev/null; then
      echo "✅ Downloaded allowed_endpoints.yaml"
      ALLOWED_ENDPOINTS=$(grep -E "^\s*-\s+" /tmp/allowed_endpoints.yaml | sed 's/^\s*-\s*//;s/#.*$//;s/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' | tr '\n' ' ')
      [ -n "$ALLOWED_ENDPOINTS" ] && echo "Extracted endpoints: $ALLOWED_ENDPOINTS" || echo "⚠️ No endpoints found in YAML"
    else
      echo "⚠️ Could not download allowed_endpoints.yaml, will skip vsock-proxy setup"
    fi
  else
    echo "Warning: Downloaded file size is suspiciously small ($FILE_SIZE bytes)"
    echo "File may be corrupted or incomplete"
    rm -f /tmp/nitro.eif
    touch /opt/nautilus/.ready
  fi
else
  echo "Warning: EIF file not found at $EIF_S3_PATH"
  echo "Will wait for manual deployment or CI/CD pipeline"
  # Create a placeholder file to indicate readiness
  touch /opt/nautilus/.ready
fi

start_enclave(){
 [ -f /opt/nautilus/nitro.eif ] || return 1
 nitro-cli terminate-enclave --all 2>/dev/null
 sleep 5
 nitro-cli run-enclave --cpu-count "$ENCLAVE_CPU" --memory "$ENCLAVE_MEMORY"M --eif-path /opt/nautilus/nitro.eif || return 1
 sleep 10
 ENCLAVE_ID=$(nitro-cli describe-enclaves|jq -r '.[0].EnclaveID//empty')
 [ -z "$ENCLAVE_ID" ] && return 1
 bash /opt/nautilus/expose_enclave.sh
 sleep 5
 PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4||echo localhost)
 curl -f "http://$PUBLIC_IP:$ENCLAVE_PORT/health_check" >/dev/null 2>&1
}
[ -f /opt/nautilus/nitro.eif ] && start_enclave
cat >/etc/systemd/system/enclave-manager.service <<EOF
[Unit]
Description=Nitro Enclave Manager
After=network.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/opt/nautilus/expose_enclave.sh
Restart=on-failure
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
${extra_user_data}

