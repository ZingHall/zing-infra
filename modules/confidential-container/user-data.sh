#!/bin/bash
# User data script for ECS confidential container instances
# This script installs and configures the ECS agent

set -e
exec > >(tee /var/log/ecs-init.log) 2>&1

CLUSTER_NAME="${cluster_name}"
REGION="${region}"
EXTRA_USER_DATA="${extra_user_data}"
AMI_OS="${ami_os}"
ENABLE_ENCLAVE_MTLS="${enable_enclave_mtls}"
MTLS_CERTIFICATE_SECRETS="${mtls_certificate_secrets}"
MTLS_CERTIFICATE_PATH="${mtls_certificate_path}"
ENCLAVE_ENDPOINTS="${enclave_endpoints}"

echo "=========================================="
echo "ECS Confidential Container Initialization"
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo "OS: $AMI_OS"
echo "Enclave mTLS: $ENABLE_ENCLAVE_MTLS"
echo "=========================================="

# Function to retry commands
retry() {
  local max_attempts=$1
  shift
  local attempt=1
  while [ $attempt -le $max_attempts ]; do
    if "$@"; then
      return 0
    fi
    echo "Command failed (attempt $attempt/$max_attempts), retrying in 5 seconds..."
    sleep 5
    attempt=$((attempt + 1))
  done
  echo "Command failed after $max_attempts attempts"
  return 1
}

# Install ECS agent based on OS
if [ "$AMI_OS" = "amazon-linux-2023" ]; then
  echo "Installing ECS agent for Amazon Linux 2023..."
  
  # Update system
  echo "Updating system packages..."
  retry 3 dnf update -y || {
    echo "⚠️  dnf update failed, continuing anyway..."
    dnf clean all || true
  }

  # Install required packages
  echo "Installing required packages..."
  retry 3 dnf install -y \
    docker \
    jq \
    aws-cli \
    curl \
    wget \
    git \
    amazon-ecs-init || {
    echo "⚠️  Some packages failed to install, continuing..."
  }

  # Start Docker
  echo "Starting Docker service..."
  systemctl enable docker
  systemctl start docker

  # Configure ECS agent
  echo "Configuring ECS agent..."
  mkdir -p /etc/ecs
  echo "ECS_CLUSTER=$CLUSTER_NAME" > /etc/ecs/ecs.config
  echo "ECS_ENABLE_CONTAINER_METADATA=true" >> /etc/ecs/ecs.config
  echo "ECS_ENGINE_TASK_CLEANUP_WAIT_DURATION=1h" >> /etc/ecs/ecs.config
  echo "ECS_CONTAINER_STOP_TIMEOUT=30s" >> /etc/ecs/ecs.config

  # Start ECS agent
  echo "Starting ECS agent..."
  systemctl enable ecs
  systemctl start ecs

elif [ "$AMI_OS" = "ubuntu" ]; then
  echo "Installing ECS agent for Ubuntu..."
  
  # Update system
  echo "Updating system packages..."
  retry 3 apt-get update -y || {
    echo "⚠️  apt-get update failed, continuing anyway..."
  }

  # Install required packages
  echo "Installing required packages..."
  retry 3 apt-get install -y \
    docker.io \
    jq \
    awscli \
    curl \
    wget \
    git \
    ca-certificates \
    gnupg \
    lsb-release || {
    echo "⚠️  Some packages failed to install, continuing..."
  }

  # Start Docker
  echo "Starting Docker service..."
  systemctl enable docker
  systemctl start docker

  # Add ECS agent repository
  echo "Adding ECS agent repository..."
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

  # Install ECS agent
  echo "Installing ECS agent..."
  curl -o /tmp/ecs-agent.deb https://s3.amazonaws.com/amazon-ecs-agent-us-east-1/ecs-agent-latest.deb || \
    curl -o /tmp/ecs-agent.deb https://s3.amazonaws.com/amazon-ecs-agent-us-west-2/ecs-agent-latest.deb
  
  if [ -f /tmp/ecs-agent.deb ]; then
    dpkg -i /tmp/ecs-agent.deb || apt-get install -f -y
  fi

  # Configure ECS agent
  echo "Configuring ECS agent..."
  mkdir -p /etc/ecs
  echo "ECS_CLUSTER=$CLUSTER_NAME" > /etc/ecs/ecs.config
  echo "ECS_ENABLE_CONTAINER_METADATA=true" >> /etc/ecs/ecs.config
  echo "ECS_ENGINE_TASK_CLEANUP_WAIT_DURATION=1h" >> /etc/ecs/ecs.config
  echo "ECS_CONTAINER_STOP_TIMEOUT=30s" >> /etc/ecs/ecs.config

  # Start ECS agent
  echo "Starting ECS agent..."
  systemctl enable ecs
  systemctl start ecs
else
  echo "⚠️  Unknown OS: $AMI_OS, skipping ECS agent installation"
fi

# Verify Docker is running
echo "Verifying Docker is running..."
retry 5 docker ps || {
  echo "⚠️  Docker verification failed"
}

# Verify ECS agent is running (for Amazon Linux)
if [ "$AMI_OS" = "amazon-linux-2023" ]; then
  echo "Verifying ECS agent is running..."
  retry 5 systemctl is-active --quiet ecs || {
    echo "⚠️  ECS agent verification failed"
  }
fi

# Configure mTLS for Enclave connectivity
if [ "$ENABLE_ENCLAVE_MTLS" = "true" ]; then
  echo ""
  echo "=========================================="
  echo "Configuring mTLS for Nitro Enclave"
  echo "=========================================="
  
  # Create certificate directory
  echo "Creating mTLS certificate directory..."
  mkdir -p "$MTLS_CERTIFICATE_PATH"
  chmod 700 "$MTLS_CERTIFICATE_PATH"
  
  # Download certificates from Secrets Manager
  if [ -n "$MTLS_CERTIFICATE_SECRETS" ]; then
    echo "Downloading mTLS certificates from Secrets Manager..."
    
    IFS=',' read -ra SECRET_ARNS <<< "$MTLS_CERTIFICATE_SECRETS"
    SECRET_INDEX=0
    
    for SECRET_ARN in "$${SECRET_ARNS[@]}"; do
      if [ -n "$SECRET_ARN" ]; then
        echo "Downloading secret: $SECRET_ARN"
        
        # Get secret value
        SECRET_VALUE=$(aws secretsmanager get-secret-value \
          --secret-id "$SECRET_ARN" \
          --region "$REGION" \
          --query 'SecretString' \
          --output text 2>/dev/null || echo "")
        
        if [ -n "$SECRET_VALUE" ]; then
          # Try to parse as JSON first (for structured secrets)
          if echo "$SECRET_VALUE" | jq -e . >/dev/null 2>&1; then
            # JSON format - extract common fields (support both client and server certs)
            CLIENT_CERT=$(echo "$SECRET_VALUE" | jq -r '.client_cert // .cert // .certificate // empty' 2>/dev/null || echo "")
            CLIENT_KEY=$(echo "$SECRET_VALUE" | jq -r '.client_key // .key // .private_key // empty' 2>/dev/null || echo "")
            SERVER_CERT=$(echo "$SECRET_VALUE" | jq -r '.server_cert // .server_certificate // empty' 2>/dev/null || echo "")
            SERVER_KEY=$(echo "$SECRET_VALUE" | jq -r '.server_key // .server_private_key // empty' 2>/dev/null || echo "")
            CA_CERT=$(echo "$SECRET_VALUE" | jq -r '.ca_cert // .ca // .ca_certificate // empty' 2>/dev/null || echo "")
            
            # Write client certificates if found (for ECS as client)
            if [ -n "$CLIENT_CERT" ] && [ "$CLIENT_CERT" != "null" ]; then
              echo "$CLIENT_CERT" > "$MTLS_CERTIFICATE_PATH/client.crt"
              chmod 600 "$MTLS_CERTIFICATE_PATH/client.crt"
              echo "  ✓ Client certificate saved"
            fi
            
            if [ -n "$CLIENT_KEY" ] && [ "$CLIENT_KEY" != "null" ]; then
              echo "$CLIENT_KEY" > "$MTLS_CERTIFICATE_PATH/client.key"
              chmod 600 "$MTLS_CERTIFICATE_PATH/client.key"
              echo "  ✓ Client key saved"
            fi
            
            # Write server certificates if found (for ECS as server)
            if [ -n "$SERVER_CERT" ] && [ "$SERVER_CERT" != "null" ]; then
              echo "$SERVER_CERT" > "$MTLS_CERTIFICATE_PATH/server.crt"
              chmod 600 "$MTLS_CERTIFICATE_PATH/server.crt"
              echo "  ✓ Server certificate saved"
            fi
            
            if [ -n "$SERVER_KEY" ] && [ "$SERVER_KEY" != "null" ]; then
              echo "$SERVER_KEY" > "$MTLS_CERTIFICATE_PATH/server.key"
              chmod 600 "$MTLS_CERTIFICATE_PATH/server.key"
              echo "  ✓ Server key saved"
            fi
            
            if [ -n "$CA_CERT" ] && [ "$CA_CERT" != "null" ]; then
              echo "$CA_CERT" > "$MTLS_CERTIFICATE_PATH/ca.crt"
              chmod 644 "$MTLS_CERTIFICATE_PATH/ca.crt"
              echo "  ✓ CA certificate saved"
            fi
          else
            # Plain text format - save with indexed filename
            FILENAME="cert-$${SECRET_INDEX}.pem"
            echo "$SECRET_VALUE" > "$MTLS_CERTIFICATE_PATH/$FILENAME"
            chmod 600 "$MTLS_CERTIFICATE_PATH/$FILENAME"
            echo "  ✓ Certificate saved as $FILENAME"
            ((SECRET_INDEX++))
          fi
        else
          echo "  ⚠️  Failed to retrieve secret: $SECRET_ARN"
        fi
      fi
    done
    
    # Verify certificates exist
    if [ -f "$MTLS_CERTIFICATE_PATH/client.crt" ] || [ -f "$MTLS_CERTIFICATE_PATH/cert-0.pem" ]; then
      echo "✓ mTLS certificates configured successfully"
      
      # List certificate files
      echo "Certificate files:"
      ls -lh "$MTLS_CERTIFICATE_PATH" || true
    else
      echo "⚠️  Warning: No mTLS certificates found. mTLS connections may fail."
    fi
  else
    echo "⚠️  Warning: No certificate secrets ARNs provided"
  fi
  
  # Create mTLS configuration file with endpoints
  if [ -n "$ENCLAVE_ENDPOINTS" ]; then
    echo "Creating Enclave endpoints configuration..."
    mkdir -p /etc/ecs/enclave
    echo "$ENCLAVE_ENDPOINTS" | tr ',' '\n' > /etc/ecs/enclave/endpoints.txt
    chmod 644 /etc/ecs/enclave/endpoints.txt
    echo "  ✓ Enclave endpoints saved:"
    cat /etc/ecs/enclave/endpoints.txt | sed 's/^/    /'
  fi
  
  echo "mTLS configuration completed"
fi

# Execute extra user data if provided
if [ -n "$EXTRA_USER_DATA" ]; then
  echo ""
  echo "Executing extra user data..."
  eval "$EXTRA_USER_DATA"
fi

echo ""
echo "=========================================="
echo "ECS initialization completed"
echo "=========================================="

