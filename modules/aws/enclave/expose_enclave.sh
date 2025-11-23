# Copyright (c), Mysten Labs, Inc.
# SPDX-License-Identifier: Apache-2.0

#!/bin/bash

# Gets the enclave id and CID
# expects there to be only one enclave running
ENCLAVE_ID=$(nitro-cli describe-enclaves | jq -r ".[0].EnclaveID")
ENCLAVE_CID=$(nitro-cli describe-enclaves | jq -r ".[0].EnclaveCID")

sleep 5

# Secrets-block
# This section will be populated by configure_enclave.sh based on secret configuration
# configure_enclave.sh will replace this section with code to:
# - Create secrets.json from AWS Secrets Manager (if using secrets)
# - Create empty secrets.json (if not using secrets)
# - Then send secrets.json via VSOCK
# 
# Default fallback (if configure_enclave.sh is not used):
cat secrets.json | socat - VSOCK-CONNECT:$ENCLAVE_CID:7777

socat TCP4-LISTEN:3000,reuseaddr,fork VSOCK-CONNECT:$ENCLAVE_CID:3000 &

# Additional port configurations will be added here by configure_enclave.sh if needed
