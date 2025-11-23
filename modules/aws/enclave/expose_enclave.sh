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
if [ ! -f /opt/nautilus/secrets.json ]; then
  echo '{}' > /opt/nautilus/secrets.json
fi

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