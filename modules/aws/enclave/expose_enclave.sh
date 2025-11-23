#!/bin/bash
# Expose enclave ports to host

set -euo pipefail

# Get ports from environment variables (set by user-data.sh) or use defaults
ENCLAVE_PORT="${ENCLAVE_PORT:-3000}"
ENCLAVE_INIT_PORT="${ENCLAVE_INIT_PORT:-3001}"

# Ensure directory exists
mkdir -p /opt/nautilus

# Get enclave ID and CID with retry logic
ENCLAVE_ID=""
ENCLAVE_CID=""
for i in {1..10}; do
  ENCLAVE_ID=$(nitro-cli describe-enclaves 2>/dev/null | jq -r '.[0].EnclaveID // empty' || echo "")
  ENCLAVE_CID=$(nitro-cli describe-enclaves 2>/dev/null | jq -r '.[0].EnclaveCID // empty' || echo "")
  
  if [ -n "$ENCLAVE_ID" ] && [ "$ENCLAVE_ID" != "null" ] && [ -n "$ENCLAVE_CID" ] && [ "$ENCLAVE_CID" != "null" ]; then
    break
  fi
  
  if [ $i -lt 10 ]; then
    echo "Waiting for enclave to start... (attempt $i/10)"
    sleep 2
  fi
done

if [ -z "$ENCLAVE_ID" ] || [ "$ENCLAVE_ID" == "null" ]; then
  echo "Error: No enclave found after retries"
  exit 1
fi

if [ -z "$ENCLAVE_CID" ] || [ "$ENCLAVE_CID" == "null" ]; then
  echo "Error: Failed to get enclave CID"
  exit 1
fi

echo "Using Enclave ID: $ENCLAVE_ID, CID: $ENCLAVE_CID"

# Kill any existing socat processes on the ports we'll use
for port in $ENCLAVE_PORT $ENCLAVE_INIT_PORT; do
  PIDS=$(sudo lsof -t -i :$port 2>/dev/null || true)
  if [ -n "$PIDS" ]; then
    echo "Killing existing processes on port $port: $PIDS"
    sudo kill -9 $PIDS || true
  fi
done

# Kill any existing socat processes connected to the enclave
pkill -f "socat.*VSOCK-CONNECT:$ENCLAVE_CID" 2>/dev/null || true

sleep 2

# Create empty secrets.json if it doesn't exist
if [ ! -f /opt/nautilus/secrets.json ]; then
  echo '{}' > /opt/nautilus/secrets.json
  echo "Created empty secrets.json"
fi

# Use compiled socat if available, otherwise fallback to system socat
SOCAT_CMD=$(command -v /usr/local/bin/socat || command -v socat || echo "socat")

if ! command -v "$SOCAT_CMD" >/dev/null 2>&1; then
  echo "Error: socat not found"
  exit 1
fi

# Retry loop for secrets.json delivery (VSOCK)
echo "Sending secrets.json to enclave via VSOCK (port 7777)..."
SECRETS_SENT=false
for i in {1..5}; do
  if timeout 5 cat /opt/nautilus/secrets.json | $SOCAT_CMD - VSOCK-CONNECT:$ENCLAVE_CID:7777 2>/dev/null; then
    echo "Successfully sent secrets.json to enclave"
    SECRETS_SENT=true
    break
  else
    echo "Failed to connect to enclave on port 7777, retrying ($i/5)..."
    sleep 2
  fi
done

if [ "$SECRETS_SENT" = false ]; then
  echo "Warning: Failed to send secrets.json to enclave after 5 attempts"
fi

# Start socat forwarders in background
echo "Exposing enclave port $ENCLAVE_PORT to host..."
$SOCAT_CMD TCP4-LISTEN:$ENCLAVE_PORT,reuseaddr,fork VSOCK-CONNECT:$ENCLAVE_CID:$ENCLAVE_PORT >/dev/null 2>&1 &
SOCAT_MAIN_PID=$!

echo "Exposing enclave port $ENCLAVE_INIT_PORT to localhost for init endpoints..."
$SOCAT_CMD TCP4-LISTEN:$ENCLAVE_INIT_PORT,bind=127.0.0.1,reuseaddr,fork VSOCK-CONNECT:$ENCLAVE_CID:$ENCLAVE_INIT_PORT >/dev/null 2>&1 &
SOCAT_INIT_PID=$!

# Wait a moment to ensure processes started
sleep 1

# Verify processes are running
if ! kill -0 $SOCAT_MAIN_PID 2>/dev/null; then
  echo "Error: Failed to start socat forwarder for port $ENCLAVE_PORT"
  exit 1
fi

if ! kill -0 $SOCAT_INIT_PID 2>/dev/null; then
  echo "Error: Failed to start socat forwarder for port $ENCLAVE_INIT_PORT"
  exit 1
fi

echo "Enclave ports exposed successfully"
echo "  - Port $ENCLAVE_PORT -> Enclave CID $ENCLAVE_CID:$ENCLAVE_PORT (PID: $SOCAT_MAIN_PID)"
echo "  - Port $ENCLAVE_INIT_PORT -> Enclave CID $ENCLAVE_CID:$ENCLAVE_INIT_PORT (PID: $SOCAT_INIT_PID)"