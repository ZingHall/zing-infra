#!/bin/bash
# SPDX-License-Identifier: Apache-2.0

# Don't exit on error - continue even if some commands fail
set +e
set +u
set +o pipefail

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
  echo "Warning: No enclave found after retries, will continue anyway"
  ENCLAVE_ID=""
fi

if [ -z "$ENCLAVE_CID" ] || [ "$ENCLAVE_CID" == "null" ]; then
  echo "Warning: Failed to get enclave CID, will continue anyway"
  ENCLAVE_CID=""
fi

if [ -n "$ENCLAVE_ID" ] && [ -n "$ENCLAVE_CID" ]; then
  echo "Using Enclave ID: $ENCLAVE_ID, CID: $ENCLAVE_CID"
else
  echo "Warning: Enclave not available (ID: $ENCLAVE_ID, CID: $ENCLAVE_CID)"
fi

# Kill any existing socat processes on the ports we'll use
for port in $ENCLAVE_PORT $ENCLAVE_INIT_PORT; do
  PIDS=$(sudo lsof -t -i :$port 2>/dev/null || true)
  if [ -n "$PIDS" ]; then
    echo "Killing existing processes on port $port: $PIDS"
    sudo kill -9 $PIDS || true
  fi
done

# Kill any existing socat processes connected to the enclave (only if CID is available)
if [ -n "$ENCLAVE_CID" ] && [ "$ENCLAVE_CID" != "null" ]; then
  pkill -f "socat.*VSOCK-CONNECT:$ENCLAVE_CID" 2>/dev/null || true
fi

sleep 2

# Create empty secrets.json if it doesn't exist
SECRETS_FILE="/opt/nautilus/secrets.json"
if [ ! -f "$SECRETS_FILE" ]; then
  echo '{}' > "$SECRETS_FILE"
  echo "Created empty secrets.json at $SECRETS_FILE"
fi

# Use compiled socat if available, otherwise fallback to system socat
SOCAT_CMD=$(command -v /usr/local/bin/socat || command -v socat || echo "socat")

if ! command -v "$SOCAT_CMD" >/dev/null 2>&1; then
  echo "Warning: socat not found, will try to continue anyway"
  # Don't exit - continue to try other operations
fi

# Retry loop for secrets.json delivery (VSOCK) - only if CID is available
if [ -n "$ENCLAVE_CID" ] && [ "$ENCLAVE_CID" != "null" ]; then
  echo "Sending secrets.json to enclave via VSOCK (port 7777)..."
  SECRETS_SENT=false
  # Wait a bit first to ensure enclave's run.sh has started listening
  sleep 5
  for i in {1..15}; do
    if timeout 3 cat "$SECRETS_FILE" | $SOCAT_CMD - VSOCK-CONNECT:$ENCLAVE_CID:7777 2>/dev/null; then
      echo "Successfully sent secrets.json to enclave"
      SECRETS_SENT=true
      break
    else
      echo "Failed to connect to enclave on port 7777, retrying ($i/15)..."
      sleep 3
    fi
  done

  if [ "$SECRETS_SENT" = false ]; then
    echo "Warning: Failed to send secrets.json to enclave after 15 attempts"
    echo "Enclave will continue with empty secrets (run.sh has 30s timeout)"
  fi
else
  echo "Warning: Cannot send secrets.json - enclave CID not available"
fi

# Start socat forwarders in background - only if CID is available
if [ -n "$ENCLAVE_CID" ] && [ "$ENCLAVE_CID" != "null" ]; then
  echo "Exposing enclave port $ENCLAVE_PORT to host..."
  $SOCAT_CMD TCP4-LISTEN:$ENCLAVE_PORT,reuseaddr,fork VSOCK-CONNECT:$ENCLAVE_CID:$ENCLAVE_PORT >/dev/null 2>&1 &
  SOCAT_MAIN_PID=$!

  echo "Exposing enclave port $ENCLAVE_INIT_PORT to localhost for init endpoints..."
  $SOCAT_CMD TCP4-LISTEN:$ENCLAVE_INIT_PORT,bind=127.0.0.1,reuseaddr,fork VSOCK-CONNECT:$ENCLAVE_CID:$ENCLAVE_INIT_PORT >/dev/null 2>&1 &
  SOCAT_INIT_PID=$!

  # Wait a moment to ensure processes started
  sleep 1

  # Verify processes are running (but don't exit on failure)
  if ! kill -0 $SOCAT_MAIN_PID 2>/dev/null; then
    echo "Warning: Failed to start socat forwarder for port $ENCLAVE_PORT"
  else
    echo "  - Port $ENCLAVE_PORT -> Enclave CID $ENCLAVE_CID:$ENCLAVE_PORT (PID: $SOCAT_MAIN_PID)"
  fi

  if ! kill -0 $SOCAT_INIT_PID 2>/dev/null; then
    echo "Warning: Failed to start socat forwarder for port $ENCLAVE_INIT_PORT"
  else
    echo "  - Port $ENCLAVE_INIT_PORT -> Enclave CID $ENCLAVE_CID:$ENCLAVE_INIT_PORT (PID: $SOCAT_INIT_PID)"
  fi
else
  echo "Warning: Cannot start socat forwarders - enclave CID not available"
  echo "  Ports $ENCLAVE_PORT and $ENCLAVE_INIT_PORT will not be forwarded"
fi

echo "Enclave port exposure completed (with warnings if any)"
