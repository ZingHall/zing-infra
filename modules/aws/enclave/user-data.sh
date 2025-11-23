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
{"logs":{"logs_collected":{"files":{"collect_list":[{"file_path":"/var/log/enclave-init.log","log_group_name":"$LOG_GROUP_NAME","log_stream_name":"{instance_id}/enclave-init.log","retention_in_days":7},{"file_path":"/var/log/enclave-console.log","log_group_name":"$LOG_GROUP_NAME","log_stream_name":"{instance_id}/enclave-console.log","retention_in_days":7},{"file_path":"/var/log/messages","log_group_name":"$LOG_GROUP_NAME","log_stream_name":"{instance_id}/messages","retention_in_days":7},{"file_path":"/var/log/secure","log_group_name":"$LOG_GROUP_NAME","log_stream_name":"{instance_id}/secure","retention_in_days":7},{"file_path":"/var/log/cloud-init.log","log_group_name":"$LOG_GROUP_NAME","log_stream_name":"{instance_id}/cloud-init.log","retention_in_days":7},{"file_path":"/var/log/cloud-init-output.log","log_group_name":"$LOG_GROUP_NAME","log_stream_name":"{instance_id}/cloud-init-output.log","retention_in_days":7}]}}}}
CW
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s
systemctl enable amazon-cloudwatch-agent
systemctl start docker && systemctl enable docker
systemctl start nitro-enclaves-allocator && systemctl enable nitro-enclaves-allocator
systemctl restart nitro-enclaves-allocator

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

# Create secrets.json BEFORE starting enclave (independent of enclave startup)
# This ensures secrets.json exists even if EIF file is missing or enclave fails to start
echo "Creating secrets.json from Secrets Manager..."
if [ -x /opt/nautilus/expose_enclave.sh ]; then
  # Extract just the secrets.json creation logic
  # We'll create a minimal version that doesn't require enclave to be running
  MTLS_SECRET_NAME="nautilus-enclave-mtls-client-cert"
  MTLS_SECRET_VALUE=$(timeout 10 aws secretsmanager get-secret-value \
    --secret-id "$MTLS_SECRET_NAME" \
    --region ap-northeast-1 \
    --query SecretString \
    --output text 2>/dev/null || echo '{}')
  
  if [ "$MTLS_SECRET_VALUE" != "{}" ] && [ -n "$MTLS_SECRET_VALUE" ] && echo "$MTLS_SECRET_VALUE" | jq empty 2>/dev/null; then
    echo "✅ Retrieved mTLS certificates from Secrets Manager"
    TMP_SECRETS=$(mktemp)
    echo "$MTLS_SECRET_VALUE" > "$TMP_SECRETS"
    
    JQ_OUTPUT=$(timeout 10 jq -n \
      --slurpfile cert_json "$TMP_SECRETS" \
      --arg endpoint "https://watermark.internal.staging.zing.you:8080" \
      '{
          MTLS_CLIENT_CERT_JSON: $cert_json[0],
          ECS_WATERMARK_ENDPOINT: $endpoint
      }' 2>&1)
    JQ_EXIT_CODE=$?
    
    if [ $JQ_EXIT_CODE -eq 0 ] && [ -n "$JQ_OUTPUT" ] && echo "$JQ_OUTPUT" | jq empty 2>/dev/null; then
      echo "$JQ_OUTPUT" | sudo tee /opt/nautilus/secrets.json > /dev/null
      sudo chmod 644 /opt/nautilus/secrets.json
      echo "✅ Created secrets.json with mTLS certificates"
    else
      echo "⚠️  jq processing failed, creating empty secrets.json"
      echo '{}' | sudo tee /opt/nautilus/secrets.json > /dev/null
      sudo chmod 644 /opt/nautilus/secrets.json
    fi
    rm -f "$TMP_SECRETS"
  else
    echo "⚠️  Failed to retrieve mTLS certificates, creating empty secrets.json"
    echo '{}' | sudo tee /opt/nautilus/secrets.json > /dev/null
    sudo chmod 644 /opt/nautilus/secrets.json
  fi
else
  echo "⚠️  expose_enclave.sh not executable, creating empty secrets.json as fallback"
  echo '{}' | sudo tee /opt/nautilus/secrets.json > /dev/null
  sudo chmod 644 /opt/nautilus/secrets.json
fi

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
    ALLOWED_ENDPOINTS=""
    if retry 3 aws s3 cp "$YAML_S3_PATH" /tmp/allowed_endpoints.yaml 2>/dev/null; then
      echo "✅ Downloaded allowed_endpoints.yaml"
      ALLOWED_ENDPOINTS=$(grep -E "^\s*-\s+" /tmp/allowed_endpoints.yaml | sed 's/^\s*-\s*//;s/#.*$//;s/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' | tr '\n' ' ')
      [ -n "$ALLOWED_ENDPOINTS" ] && echo "Extracted endpoints: $ALLOWED_ENDPOINTS" || echo "⚠️ No endpoints found in YAML"
      
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
        echo "vsock-proxy configuration completed"
      else
        echo "No allowed endpoints configured, skipping vsock-proxy setup"
      fi
    else
      echo "⚠️ Could not download allowed_endpoints.yaml, will skip vsock-proxy setup"
    fi
    
    # Configure vsock-proxy AFTER downloading allowed_endpoints.yaml
    if [ -n "$ALLOWED_ENDPOINTS" ]; then
      echo "Configuring vsock-proxy with endpoints: $ALLOWED_ENDPOINTS"
      sudo mkdir -p /etc/nitro_enclaves
      [ -f /etc/nitro_enclaves/vsock-proxy.yaml ] && sudo cp /etc/nitro_enclaves/vsock-proxy.yaml /etc/nitro_enclaves/vsock-proxy.yaml.bak
      
      # Create vsock-proxy.yaml using bash (no Python dependency)
      T=$(mktemp)
      echo "allowlist:">"$T"
      
      # Extract existing endpoints from backup if it exists
      if [ -f /etc/nitro_enclaves/vsock-proxy.yaml.bak ]; then
        sudo grep -E "^\s*-\s*\{address:" /etc/nitro_enclaves/vsock-proxy.yaml.bak 2>/dev/null | \
          sed -E 's/.*\{address:\s*([^,]+),\s*port:\s*([0-9]+)\}.*/\1 \2/' | \
          sort -u | while read h p; do
            [ -n "$h" ] && printf "  - address: %s\n    port: %s\n" "$h" "$${p:-443}">>"$T"
          done
      fi
      
      # Add new endpoints from ALLOWED_ENDPOINTS
      for ep in $ALLOWED_ENDPOINTS; do
        # Check if endpoint contains port (has colon)
        if echo "$ep" | grep -q ':'; then
          h=$(echo "$ep"|sed 's/:.*$//')
          p=$(echo "$ep"|sed 's/^[^:]*://')
        else
          # No port specified, use default 443
          h="$ep"
          p=443
        fi
        # Ensure port is numeric (default to 443 if invalid)
        case "$p" in
          ''|*[!0-9]*) p=443 ;;
        esac
        grep -q "address: $h" "$T" || printf "  - address: %s\n    port: %s\n" "$h" "$p">>"$T"
      done
      
      sudo mv "$T" /etc/nitro_enclaves/vsock-proxy.yaml
      PORT=8101
      for ep in $ALLOWED_ENDPOINTS; do
        # Extract hostname (same logic as above)
        if echo "$ep" | grep -q ':'; then
          h=$(echo "$ep"|sed 's/:.*$//')
          p=$(echo "$ep"|sed 's/^[^:]*://')
        else
          h="$ep"
          p=443
        fi
        # Ensure port is numeric (default to 443 if invalid)
        case "$p" in
          ''|*[!0-9]*) p=443 ;;
        esac
        sudo pkill -f "vsock-proxy $PORT" 2>/dev/null || true
        sleep 1
        sudo vsock-proxy $PORT $h $p --config /etc/nitro_enclaves/vsock-proxy.yaml &
        PORT=$((PORT+1))
      done
      echo "✅ vsock-proxy configuration completed"
    else
      echo "⚠️ No allowed endpoints configured, skipping vsock-proxy setup"
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
 echo "=========================================="
 echo "Starting Nitro Enclave..."
 echo "=========================================="
 
 # Step 1: Check EIF file exists
 echo "[DEBUG] Step 1: Checking EIF file..."
 if [ ! -f /opt/nautilus/nitro.eif ]; then
   echo "❌ [DEBUG] EIF file not found: /opt/nautilus/nitro.eif"
   return 1
 fi
 EIF_SIZE=$(stat -f%z /opt/nautilus/nitro.eif 2>/dev/null || stat -c%s /opt/nautilus/nitro.eif 2>/dev/null || echo "0")
 echo "✅ [DEBUG] EIF file found: /opt/nautilus/nitro.eif (size: $EIF_SIZE bytes)"
 
 # Step 2: Terminate any existing enclaves
 echo "[DEBUG] Step 2: Terminating existing enclaves..."
 if nitro-cli terminate-enclave --all 2>/dev/null; then
   echo "✅ [DEBUG] Terminated existing enclaves (if any)"
 else
   echo "⚠️  [DEBUG] No existing enclaves to terminate (this is OK)"
 fi
 sleep 5
 
 # Step 3: Start the enclave
 echo "[DEBUG] Step 3: Starting enclave..."
 echo "  CPU: $ENCLAVE_CPU"
 echo "  Memory: $ENCLAVE_MEMORY""M"
 echo "  EIF Path: /opt/nautilus/nitro.eif"
 
 if ! nitro-cli run-enclave --cpu-count "$ENCLAVE_CPU" --memory "$ENCLAVE_MEMORY""M" --eif-path /opt/nautilus/nitro.eif; then
   echo "❌ [DEBUG] Failed to start enclave"
   echo "[DEBUG] Checking nitro-cli error output..."
   nitro-cli describe-enclaves 2>&1 || true
   return 1
 fi
 echo "✅ [DEBUG] Enclave start command completed"
 
 # Step 4: Wait for enclave to be ready
 echo "[DEBUG] Step 4: Waiting for enclave to be ready..."
 sleep 10
 
 # Step 5: Verify enclave is running
 echo "[DEBUG] Step 5: Verifying enclave is running..."
 ENCLAVE_ID=$(nitro-cli describe-enclaves 2>/dev/null | jq -r '.[0].EnclaveID//empty' || echo "")
 if [ -z "$ENCLAVE_ID" ] || [ "$ENCLAVE_ID" = "null" ]; then
   echo "❌ [DEBUG] Enclave ID not found after startup"
   echo "[DEBUG] Full enclave status:"
   nitro-cli describe-enclaves 2>&1 || true
   return 1
 fi
 ENCLAVE_CID=$(nitro-cli describe-enclaves 2>/dev/null | jq -r '.[0].EnclaveCID//empty' || echo "")
 echo "✅ [DEBUG] Enclave is running:"
 echo "  Enclave ID: $ENCLAVE_ID"
 echo "  Enclave CID: $ENCLAVE_CID"
 
 # Step 6: Run expose_enclave.sh
 echo "[DEBUG] Step 6: Running expose_enclave.sh..."
 if [ ! -x /opt/nautilus/expose_enclave.sh ]; then
   echo "❌ [DEBUG] expose_enclave.sh is not executable"
   return 1
 fi
 if ! bash /opt/nautilus/expose_enclave.sh; then
   echo "❌ [DEBUG] expose_enclave.sh failed"
   echo "[DEBUG] Checking for socat processes..."
   ps aux | grep '[s]ocat' || echo "No socat processes found"
   return 1
 fi
 echo "✅ [DEBUG] expose_enclave.sh completed"
 
 # Step 7: Wait for services to be ready
 echo "[DEBUG] Step 7: Waiting for services to be ready..."
 sleep 5
 
 # Step 8: Check socat processes
 echo "[DEBUG] Step 8: Checking port forwarding..."
 SOCAT_COUNT=$(pgrep -f "socat.*VSOCK-CONNECT" | wc -l)
 echo "  Found $SOCAT_COUNT socat process(es)"
 if [ "$SOCAT_COUNT" -eq 0 ]; then
   echo "⚠️  [DEBUG] Warning: No socat processes found"
 fi
 
 # Check listening ports
 for port in 3000 3001; do
   if sudo lsof -i :$port >/dev/null 2>&1; then
     echo "  ✅ Port $port is listening"
   else
     echo "  ⚠️  Port $port is not listening"
   fi
 done
 
 # Step 9: Test health check endpoint
 echo "[DEBUG] Step 9: Testing health check endpoint..."
 PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "localhost")
 echo "  Public IP: $PUBLIC_IP"
 echo "  Health check URL: http://$PUBLIC_IP:$ENCLAVE_PORT/health_check"
 
 if curl -f -s --max-time 10 "http://$PUBLIC_IP:$ENCLAVE_PORT/health_check" >/dev/null 2>&1; then
   echo "✅ [DEBUG] Health check passed"
 else
   echo "⚠️  [DEBUG] Health check failed (this may be OK if enclave is still starting)"
   echo "[DEBUG] Trying localhost instead..."
   if curl -f -s --max-time 10 "http://localhost:$ENCLAVE_PORT/health_check" >/dev/null 2>&1; then
     echo "✅ [DEBUG] Health check passed on localhost"
   else
     echo "⚠️  [DEBUG] Health check failed on localhost too"
     echo "[DEBUG] This might be normal if the enclave is still initializing"
   fi
 fi
 
 echo "=========================================="
 echo "✅ Enclave startup sequence completed"
 echo "=========================================="
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

