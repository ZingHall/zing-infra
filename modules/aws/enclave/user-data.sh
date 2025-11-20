#!/bin/bash
# User data script for Nitro Enclave EC2 instances
# This script initializes the instance and deploys the enclave

set -e
exec > >(tee /var/log/enclave-init.log) 2>&1

S3_BUCKET="${s3_bucket}"
EIF_VERSION="${eif_version}"
EIF_PATH="${eif_path}"
ENCLAVE_CPU="${enclave_cpu}"
ENCLAVE_MEMORY="${enclave_memory}"
ENCLAVE_PORT="${enclave_port}"
ENCLAVE_INIT_PORT="${enclave_init_port}"
NAME="${name}"
REGION="${region}"

echo "=========================================="
echo "Nitro Enclave Initialization Script"
echo "Instance: $NAME"
echo "Region: $REGION"
echo "=========================================="

# Update system
echo "Updating system packages..."
yum update -y

# Install required packages
echo "Installing required packages..."

# Enable amazon-linux-extras for Nitro Enclaves
echo "Enabling amazon-linux-extras for Nitro Enclaves..."
amazon-linux-extras enable aws-nitro-enclaves-cli

# Install base packages
yum install -y \
  docker \
  jq \
  aws-cli \
  curl \
  wget \
  git

# Install build tools for compiling socat with VSOCK support
yum groupinstall -y "Development Tools" || true
yum install -y openssl-devel

# Install Nitro Enclaves CLI (after enabling extras)
echo "Installing Nitro Enclaves CLI..."
yum install -y aws-nitro-enclaves-cli aws-nitro-enclaves-cli-devel

# Add ec2-user to ne and docker groups
echo "Configuring user groups..."
usermod -aG ne ec2-user
usermod -aG docker ec2-user

# Compile socat with VSOCK support (standard socat package doesn't support VSOCK)
echo "Compiling socat with VSOCK support..."
cd /tmp
if [ ! -f "socat-1.7.4.4.tar.gz" ]; then
  wget -q http://www.dest-unreach.org/socat/download/socat-1.7.4.4.tar.gz || \
    wget -q https://github.com/craigsdennis/socat/archive/refs/tags/v1.7.4.4.tar.gz -O socat-1.7.4.4.tar.gz || \
    (echo "Warning: Failed to download socat source, will try to use system socat" && touch /tmp/socat-download-failed)
fi

if [ ! -f "/tmp/socat-download-failed" ]; then
  tar -xzf socat-1.7.4.4.tar.gz
  cd socat-1.7.4.4 || cd socat-1.7.4.4
  ./configure --enable-vsock
  make
  make install
  echo "✅ socat compiled with VSOCK support"
  
  # Verify installation
  if /usr/local/bin/socat -h 2>&1 | grep -q "VSOCK"; then
    echo "✅ Verified: socat supports VSOCK"
  else
    echo "⚠️  Warning: socat may not support VSOCK"
  fi
else
  echo "⚠️  Warning: Using system socat (may not support VSOCK)"
  # Fallback: install system socat
  yum install -y socat || true
fi

# Configure udev rules for vsock access
echo "Configuring udev rules..."
echo 'KERNEL=="vsock", MODE="660", GROUP="ne"' > /etc/udev/rules.d/51-vsock.rules
udevadm control --reload-rules
udevadm trigger

# Start and enable Docker
echo "Starting Docker service..."
systemctl start docker
systemctl enable docker

# Start and enable Nitro Enclaves
echo "Starting Nitro Enclaves service..."
systemctl start nitro-enclaves-allocator
systemctl enable nitro-enclaves-allocator

# Restart allocator to ensure udev rules are applied
echo "Restarting nitro-enclaves-allocator to apply udev rules..."
systemctl restart nitro-enclaves-allocator

# Create enclave directory
echo "Creating enclave directory..."
mkdir -p /opt/nautilus
cd /opt/nautilus

# Download expose_enclave.sh script if not present
if [ ! -f "/opt/nautilus/expose_enclave.sh" ]; then
  echo "Creating expose_enclave.sh script..."
  cat > /opt/nautilus/expose_enclave.sh << EXPOSE_SCRIPT
#!/bin/bash
# Expose enclave ports to host

ENCLAVE_ID=\$(nitro-cli describe-enclaves | jq -r '.[0].EnclaveID // empty')
ENCLAVE_CID=\$(nitro-cli describe-enclaves | jq -r '.[0].EnclaveCID // empty')

if [ -z "\$ENCLAVE_ID" ]; then
  echo "Error: No enclave found"
  exit 1
fi

echo "Using Enclave ID: \$ENCLAVE_ID, CID: \$ENCLAVE_CID"

# Kill any existing socat processes
for port in ${enclave_port} ${enclave_init_port}; do
  PIDS=\$(sudo lsof -t -i :\$port 2>/dev/null || true)
  if [ -n "\$PIDS" ]; then
    echo "Killing processes on port \$port: \$PIDS"
    sudo kill -9 \$PIDS || true
  fi
done

sleep 2

# Create empty secrets.json
echo '{}' > /opt/nautilus/secrets.json

# Use compiled socat if available, otherwise fallback to system socat
SOCAT_CMD=\$(command -v /usr/local/bin/socat || command -v socat || echo "socat")

# Retry loop for secrets.json delivery (VSOCK)
for i in {1..5}; do
  cat /opt/nautilus/secrets.json | \$SOCAT_CMD - VSOCK-CONNECT:\$ENCLAVE_CID:7777 && break
  echo "Failed to connect to enclave on port 7777, retrying (\$i/5)..."
  sleep 2
done

# Start socat forwarders
echo "Exposing enclave port ${enclave_port} to host..."
\$SOCAT_CMD TCP4-LISTEN:${enclave_port},reuseaddr,fork VSOCK-CONNECT:\$ENCLAVE_CID:${enclave_port} &

echo "Exposing enclave port ${enclave_init_port} to localhost for init endpoints..."
\$SOCAT_CMD TCP4-LISTEN:${enclave_init_port},bind=127.0.0.1,reuseaddr,fork VSOCK-CONNECT:\$ENCLAVE_CID:${enclave_init_port} &

echo "Enclave ports exposed successfully"
EXPOSE_SCRIPT
  chmod +x /opt/nautilus/expose_enclave.sh
fi

# Download EIF file from S3
echo "Downloading EIF file from S3..."
EIF_S3_PATH="s3://${s3_bucket}/${eif_path}/nitro-${eif_version}.eif"

echo "EIF S3 path: $EIF_S3_PATH"

# Download to temporary location first, then move to final location
# This ensures we don't have a partial/corrupted file in the final location
if aws s3 ls "$EIF_S3_PATH" 2>/dev/null; then
  echo "Found EIF file: $EIF_S3_PATH"
  echo "Downloading to temporary location..."
  aws s3 cp "$EIF_S3_PATH" /tmp/nitro.eif
  
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

# Function to start enclave
start_enclave() {
  if [ -f "/opt/nautilus/nitro.eif" ]; then
    echo "Stopping any existing enclaves..."
    nitro-cli terminate-enclave --all || true
    sleep 5

    echo "Starting Nitro Enclave..."
    echo "  CPU: $ENCLAVE_CPU"
    echo "  Memory: $ENCLAVE_MEMORY MB"
    echo "  EIF: /opt/nautilus/nitro.eif"
    
    nitro-cli run-enclave \
      --cpu-count "$ENCLAVE_CPU" \
      --memory "$ENCLAVE_MEMORY"M \
      --eif-path /opt/nautilus/nitro.eif || {
      echo "Error: Failed to start enclave"
      return 1
    }

    echo "Waiting for enclave to initialize..."
    sleep 10

    # Verify enclave is running
    ENCLAVE_ID=$(nitro-cli describe-enclaves | jq -r '.[0].EnclaveID // empty')
    if [ -z "$ENCLAVE_ID" ]; then
      echo "Error: Enclave failed to start"
      return 1
    fi

    echo "Enclave started successfully: $ENCLAVE_ID"

    # Expose ports
    echo "Exposing enclave ports..."
    bash /opt/nautilus/expose_enclave.sh

    # Health check
    echo "Performing health check..."
    sleep 5
    PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo "localhost")
    
    if curl -f "http://$PUBLIC_IP:$ENCLAVE_PORT/health_check" > /dev/null 2>&1; then
      echo "Health check passed!"
    else
      echo "Warning: Health check failed, but enclave is running"
    fi

    return 0
  else
    echo "EIF file not found, skipping enclave startup"
    return 1
  fi
}

# Start enclave if EIF is available
if [ -f "/opt/nautilus/nitro.eif" ]; then
  start_enclave
fi

# Create systemd service for enclave management (optional)
cat > /etc/systemd/system/enclave-manager.service << EOF
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

# Log instance metadata
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo "N/A")
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

echo "=========================================="
echo "Initialization Complete"
echo "Instance ID: $INSTANCE_ID"
echo "Public IP: $PUBLIC_IP"
echo "Private IP: $PRIVATE_IP"
echo "Enclave Port: $ENCLAVE_PORT"
echo "=========================================="

# Execute any extra user data
${extra_user_data}

echo "User data script completed successfully"

