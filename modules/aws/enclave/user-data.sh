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
yum install -y \
  docker \
  jq \
  aws-cli \
  nitro-enclaves-cli \
  nitro-enclaves-cli-devel \
  socat \
  curl \
  wget \
  git

# Start and enable Docker
echo "Starting Docker service..."
systemctl start docker
systemctl enable docker

# Start and enable Nitro Enclaves
echo "Starting Nitro Enclaves service..."
systemctl start nitro-enclaves
systemctl enable nitro-enclaves

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

ENCLAVE_ID=\$(sudo nitro-cli describe-enclaves | jq -r '.[0].EnclaveID // empty')
ENCLAVE_CID=\$(sudo nitro-cli describe-enclaves | jq -r '.[0].EnclaveCID // empty')

if [ -z "\$ENCLAVE_ID" ]; then
  echo "Error: No enclave found"
  exit 1
fi

echo "Using Enclave ID: \$ENCLAVE_ID, CID: \$ENCLAVE_CID"

# Kill any existing socat processes
for port in ${ENCLAVE_PORT} ${ENCLAVE_INIT_PORT}; do
  PIDS=\$(sudo lsof -t -i :\$port 2>/dev/null || true)
  if [ -n "\$PIDS" ]; then
    echo "Killing processes on port \$port: \$PIDS"
    sudo kill -9 \$PIDS || true
  fi
done

sleep 2

# Create empty secrets.json
echo '{}' > /opt/nautilus/secrets.json

# Retry loop for secrets.json delivery (VSOCK)
for i in {1..5}; do
  cat /opt/nautilus/secrets.json | socat - VSOCK-CONNECT:\$ENCLAVE_CID:7777 && break
  echo "Failed to connect to enclave on port 7777, retrying (\$i/5)..."
  sleep 2
done

# Start socat forwarders
echo "Exposing enclave port ${ENCLAVE_PORT} to host..."
socat TCP4-LISTEN:${ENCLAVE_PORT},reuseaddr,fork VSOCK-CONNECT:\$ENCLAVE_CID:${ENCLAVE_PORT} &

echo "Exposing enclave port ${ENCLAVE_INIT_PORT} to localhost for init endpoints..."
socat TCP4-LISTEN:${ENCLAVE_INIT_PORT},bind=127.0.0.1,reuseaddr,fork VSOCK-CONNECT:\$ENCLAVE_CID:${ENCLAVE_INIT_PORT} &

echo "Enclave ports exposed successfully"
EXPOSE_SCRIPT
  chmod +x /opt/nautilus/expose_enclave.sh
fi

# Download EIF file from S3
echo "Downloading EIF file from S3..."
EIF_S3_PATH="s3://${S3_BUCKET}/${EIF_PATH}/nitro-${EIF_VERSION}.eif"

if aws s3 ls "$EIF_S3_PATH" 2>/dev/null; then
  echo "Found EIF file: $EIF_S3_PATH"
  aws s3 cp "$EIF_S3_PATH" /opt/nautilus/nitro.eif
  echo "EIF file downloaded successfully"
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
    sudo nitro-cli terminate-enclave --all || true
    sleep 5

    echo "Starting Nitro Enclave..."
    echo "  CPU: $ENCLAVE_CPU"
    echo "  Memory: ${ENCLAVE_MEMORY}MB"
    echo "  EIF: /opt/nautilus/nitro.eif"
    
    sudo nitro-cli run-enclave \
      --cpu-count "$ENCLAVE_CPU" \
      --memory "${ENCLAVE_MEMORY}M" \
      --eif-path /opt/nautilus/nitro.eif || {
      echo "Error: Failed to start enclave"
      return 1
    }

    echo "Waiting for enclave to initialize..."
    sleep 10

    # Verify enclave is running
    ENCLAVE_ID=$(sudo nitro-cli describe-enclaves | jq -r '.[0].EnclaveID // empty')
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
    
    if curl -f "http://${PUBLIC_IP}:${ENCLAVE_PORT}/health_check" > /dev/null 2>&1; then
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

