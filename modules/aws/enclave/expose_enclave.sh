#!/bin/bash
# SPDX-License-Identifier: Apache-2.0

# Don't exit on error - continue even if some commands fail
set +e
set +u
set +o pipefail

# Get ports from environment variables (set by user-data.sh) or use defaults
ENCLAVE_PORT="${ENCLAVE_PORT:-3000}"
ENCLAVE_INIT_PORT="${ENCLAVE_INIT_PORT:-3001}"

# Ensure directory exists with proper permissions
sudo mkdir -p /opt/nautilus
sudo chmod 755 /opt/nautilus

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
  echo '{}' | sudo tee "$SECRETS_FILE" > /dev/null
  sudo chmod 644 "$SECRETS_FILE"
  echo "Created empty secrets.json at $SECRETS_FILE"
fi

# Use compiled socat if available, otherwise fallback to system socat
SOCAT_CMD=$(command -v /usr/local/bin/socat || command -v socat || echo "socat")

if ! command -v "$SOCAT_CMD" >/dev/null 2>&1; then
  echo "Warning: socat not found, will try to continue anyway"
  # Don't exit - continue to try other operations
fi

# Send secrets.json to enclave via VSOCK (port 7777) - non-blocking
# The enclave's run.sh now starts immediately with a background listener, so we can try to send
# but don't need to wait or retry extensively since the listener is always running
if [ -n "$ENCLAVE_CID" ] && [ "$ENCLAVE_CID" != "null" ]; then
  echo "Sending secrets.json to enclave via VSOCK (port 7777)..."
  
  # Wait longer for enclave to fully start its VSOCK listener
  # The enclave needs time to: start socat listeners, start background secrets listener
  echo "Waiting for enclave VSOCK listener to be ready..."
  sleep 8
  
  # Test if VSOCK port 7777 is accepting connections before sending secrets
  VSOCK_READY=false
  for test_attempt in {1..5}; do
    if echo "test" | timeout 2 $SOCAT_CMD - VSOCK-CONNECT:$ENCLAVE_CID:7777 2>/dev/null; then
      VSOCK_READY=true
      echo "✅ VSOCK port 7777 is accepting connections"
      break
    else
      echo "⏳ VSOCK listener not ready yet (attempt $test_attempt/5)..."
      sleep 2
    fi
  done
  
  if [ "$VSOCK_READY" = "true" ]; then
    # Try to send secrets with longer timeout
    if timeout 5 cat "$SECRETS_FILE" | $SOCAT_CMD - VSOCK-CONNECT:$ENCLAVE_CID:7777 2>/dev/null; then
      echo "✅ Successfully sent secrets.json to enclave"
    else
      echo "⚠️  Could not send secrets (timeout or connection refused)"
      echo "   Will retry in background..."
      
      # Retry in background with exponential backoff
      (
        for i in 1 2 3 4 5; do
          WAIT_TIME=$((2 ** i))  # 2, 4, 8, 16, 32 seconds
          sleep $WAIT_TIME
          if timeout 5 cat "$SECRETS_FILE" | $SOCAT_CMD - VSOCK-CONNECT:$ENCLAVE_CID:7777 2>/dev/null; then
            echo "✅ Secrets sent successfully on retry attempt $i (after ${WAIT_TIME}s)"
            exit 0
          fi
        done
        echo "⚠️  Secrets not sent after all retries (enclave will continue without them)"
      ) &
    fi
  else
    echo "⚠️  VSOCK listener not responding after multiple attempts"
    echo "   Secrets can be sent later via the /api/secrets endpoint if available"
  fi
else
  echo "Warning: Cannot send secrets.json - enclave CID not available"
fi

# Start socat forwarders in background - only if CID is available
if [ -n "$ENCLAVE_CID" ] && [ "$ENCLAVE_CID" != "null" ]; then
  # Wait for enclave VSOCK listeners on ports 3000 and 3001 to be ready
  echo "Checking if enclave VSOCK listeners are ready on ports $ENCLAVE_PORT and $ENCLAVE_INIT_PORT..."
  
  # Test port 3000
  for test_attempt in {1..5}; do
    if echo "test" | timeout 1 $SOCAT_CMD - VSOCK-CONNECT:$ENCLAVE_CID:$ENCLAVE_PORT 2>/dev/null; then
      echo "✅ Enclave VSOCK listener on port $ENCLAVE_PORT is ready"
      break
    else
      if [ $test_attempt -lt 5 ]; then
        echo "⏳ Waiting for port $ENCLAVE_PORT... (attempt $test_attempt/5)"
        sleep 2
      else
        echo "⚠️  Port $ENCLAVE_PORT not responding, will start forwarder anyway"
      fi
    fi
  done
  
  # Test port 3001
  for test_attempt in {1..5}; do
    if echo "test" | timeout 1 $SOCAT_CMD - VSOCK-CONNECT:$ENCLAVE_CID:$ENCLAVE_INIT_PORT 2>/dev/null; then
      echo "✅ Enclave VSOCK listener on port $ENCLAVE_INIT_PORT is ready"
      break
    else
      if [ $test_attempt -lt 5 ]; then
        echo "⏳ Waiting for port $ENCLAVE_INIT_PORT... (attempt $test_attempt/5)"
        sleep 2
      else
        echo "⚠️  Port $ENCLAVE_INIT_PORT not responding, will start forwarder anyway"
      fi
    fi
  done
  
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
