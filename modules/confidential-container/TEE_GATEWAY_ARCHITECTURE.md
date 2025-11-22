# TEE as Gateway Architecture

This document describes the architecture where **Nitro Enclave (TEE) acts as a Gateway** that handles encryption/decryption and delegates processing to ECS containers.

## Architecture Overview

```
┌──────────────┐
│   External   │
│   Client     │
└──────┬───────┘
       │ HTTPS/mTLS
       │ (Encrypted Data)
       ▼
┌─────────────────────────────────┐
│  Nitro Enclave (TEE)            │
│  = Gateway / Service            │
│                                 │
│  1. Receives encrypted request  │
│  2. Decrypts sensitive data     │
│  3. Calls ECS service           │
│  4. Receives processed result   │
│  5. Encrypts result             │
│  6. Returns encrypted response  │
└──────┬──────────────────────────┘
       │ mTLS (Decrypted Data)
       │ TEE → ECS
       ▼
┌─────────────────────────────────┐
│  ECS Confidential Container      │
│  = Processing Service            │
│                                 │
│  - Receives decrypted data      │
│  - Performs business logic      │
│  - Returns processed result     │
│  - Never sees encrypted data    │
└─────────────────────────────────┘
```

## Connection Flow

### 1. External → TEE (Gateway)
- **Protocol**: HTTPS/mTLS
- **Direction**: External client → TEE
- **Data**: Encrypted sensitive information
- **TEE Role**: Server (receives requests)

### 2. TEE → ECS (Processing)
- **Protocol**: mTLS
- **Direction**: TEE → ECS
- **Data**: Decrypted data (plaintext)
- **TEE Role**: Client (initiates connection)
- **ECS Role**: Server (processes requests)

### 3. ECS → TEE (Result)
- **Protocol**: mTLS
- **Direction**: ECS → TEE
- **Data**: Processed result (plaintext)
- **ECS Role**: Server (returns response)
- **TEE Role**: Client (receives response)

### 4. TEE → External (Response)
- **Protocol**: HTTPS/mTLS
- **Direction**: TEE → External client
- **Data**: Encrypted result
- **TEE Role**: Server (returns response)

## Configuration for TEE as Gateway

In this architecture, you need to configure **two separate mTLS connections**:

### Connection 1: External → TEE (Gateway)
Configured in your **Nitro Enclave deployment**:
- TEE acts as **server** (listens for external requests)
- Uses server certificate for mTLS
- Handles encryption/decryption

### Connection 2: TEE → ECS (Processing)
Configured in **this module** (confidential-container):
- ECS acts as **server** (listens for TEE requests)
- ECS uses server certificate
- TEE uses client certificate to connect to ECS

## Implementation Steps

### Step 1: Configure ECS as Server for TEE

The ECS cluster needs to:
1. Listen on a port for incoming connections from TEE
2. Use server certificate for mTLS
3. Accept connections from TEE security group

```hcl
module "confidential_cluster" {
  source = "../../modules/confidential-container"

  name    = "confidential-cluster"
  vpc_id  = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids

  instance_type = "m6a.large"
  ami_os         = "amazon-linux-2023"

  # Enable mTLS - ECS will be SERVER for TEE connections
  enable_enclave_mtls = true
  
  # TEE security group (TEE will connect as CLIENT)
  enclave_security_group_ids = [
    data.aws_security_group.enclave.id
  ]
  
  # ECS service endpoints (where TEE should connect)
  enclave_endpoints = [
    "confidential-cluster.internal:8080"  # ECS service port
  ]
  
  # ECS SERVER certificates (for accepting TEE connections)
  mtls_certificate_secrets_arns = [
    aws_secretsmanager_secret.ecs_server_cert.arn
  ]

  tags = {
    Environment = "production"
    Role        = "processing-service"  # ECS is processing service
  }
}
```

### Step 2: Generate Certificates

You need **two sets of certificates**:

#### A. ECS Server Certificates (for TEE to connect)

```bash
# Create CA for ECS-TEE communication
openssl genrsa -out ecs-ca.key 4096
openssl req -new -x509 -days 365 -key ecs-ca.key -out ecs-ca.crt \
  -subj "/CN=ECS-TEE-CA"

# Create ECS server certificate
openssl genrsa -out ecs-server.key 4096
openssl req -new -key ecs-server.key -out ecs-server.csr \
  -subj "/CN=ECS-Server"

# Sign ECS server certificate
openssl x509 -req -days 365 -in ecs-server.csr -CA ecs-ca.crt -CAkey ecs-ca.key \
  -CAcreateserial -out ecs-server.crt

# Create TEE client certificate (for TEE to authenticate to ECS)
openssl genrsa -out tee-client.key 4096
openssl req -new -key tee-client.key -out tee-client.csr \
  -subj "/CN=TEE-Client"

# Sign TEE client certificate
openssl x509 -req -days 365 -in tee-client.csr -CA ecs-ca.crt -CAkey ecs-ca.key \
  -CAcreateserial -out tee-client.crt
```

#### B. Store ECS Server Certificates in Secrets Manager

```hcl
# ECS server certificate (ECS uses this to accept TEE connections)
resource "aws_secretsmanager_secret" "ecs_server_cert" {
  name        = "ecs-server-mtls-cert"
  description = "Server certificates for ECS to accept TEE connections"
  
  tags = {
    Purpose = "mTLS"
    Role    = "server"  # ECS is server
    Cluster = "confidential-cluster"
  }
}

resource "aws_secretsmanager_secret_version" "ecs_server_cert" {
  secret_id = aws_secretsmanager_secret.ecs_server_cert.id
  
  secret_string = jsonencode({
    server_cert = file("${path.module}/certs/ecs-server.crt")  # ECS server cert
    server_key  = file("${path.module}/certs/ecs-server.key")   # ECS server key
    ca_cert     = file("${path.module}/certs/ecs-ca.crt")      # CA to verify TEE client
  })
}

# TEE client certificate (TEE uses this to connect to ECS)
# Store this in Enclave's Secrets Manager or pass to Enclave deployment
resource "aws_secretsmanager_secret" "tee_client_cert" {
  name        = "tee-client-mtls-cert"
  description = "Client certificates for TEE to connect to ECS"
  
  tags = {
    Purpose = "mTLS"
    Role    = "client"  # TEE is client when connecting to ECS
    Service = "enclave"
  }
}

resource "aws_secretsmanager_secret_version" "tee_client_cert" {
  secret_id = aws_secretsmanager_secret.tee_client_cert.id
  
  secret_string = jsonencode({
    client_cert = file("${path.module}/certs/tee-client.crt")  # TEE client cert
    client_key  = file("${path.module}/certs/tee-client.key")  # TEE client key
    ca_cert     = file("${path.module}/certs/ecs-ca.crt")      # CA to verify ECS server
  })
}
```

### Step 3: Configure Security Groups

```hcl
# ECS security group allows inbound from TEE
resource "aws_security_group_rule" "ecs_from_tee" {
  type                     = "ingress"
  from_port                = 8080  # ECS service port
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = data.aws_security_group.enclave.id
  security_group_id        = module.confidential_cluster.security_group_id
  description              = "Allow mTLS from TEE Gateway"
}

# TEE security group allows outbound to ECS
resource "aws_security_group_rule" "tee_to_ecs" {
  type                     = "egress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = module.confidential_cluster.security_group_id
  security_group_id        = data.aws_security_group.enclave.id
  description              = "Allow mTLS to ECS processing service"
}
```

### Step 4: Update ECS Container Application

Your ECS container needs to:
1. Listen on port 8080 (or configured port)
2. Accept mTLS connections from TEE
3. Use server certificate for mTLS

#### Python Example (ECS Server)

```python
import ssl
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

# Certificate paths (from /etc/ecs/mtls)
CERT_DIR = "/etc/ecs/mtls"
SERVER_CERT = f"{CERT_DIR}/server.crt"  # ECS server certificate
SERVER_KEY = f"{CERT_DIR}/server.key"   # ECS server key
CA_CERT = f"{CERT_DIR}/ca.crt"         # CA to verify TEE client

class ProcessingHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        # Receive decrypted data from TEE
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        data = json.loads(post_data.decode('utf-8'))
        
        # Process the data (business logic)
        result = process_data(data)
        
        # Return processed result to TEE
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(result).encode('utf-8'))
    
    def log_message(self, format, *args):
        # Suppress default logging
        pass

def process_data(data):
    """Your business logic here"""
    # Process decrypted data
    processed = {
        "status": "processed",
        "data": data  # Example: process the data
    }
    return processed

# Create SSL context for mTLS server
context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
context.load_cert_chain(SERVER_CERT, SERVER_KEY)
context.load_verify_locations(CA_CERT)
context.verify_mode = ssl.CERT_REQUIRED  # Require client certificate

# Start HTTPS server
server = HTTPServer(('0.0.0.0', 8080), ProcessingHandler)
server.socket = context.wrap_socket(server.socket, server_side=True)
print("ECS Processing Service listening on port 8080 (mTLS)")
server.serve_forever()
```

#### TEE Side (Client to ECS)

```python
import ssl
import requests
import json

# TEE client certificate paths
CERT_DIR = "/opt/enclave/certs"
CLIENT_CERT = f"{CERT_DIR}/tee-client.crt"
CLIENT_KEY = f"{CERT_DIR}/tee-client.key"
CA_CERT = f"{CERT_DIR}/ecs-ca.crt"

# ECS service endpoint
ECS_URL = "https://confidential-cluster.internal:8080"

def call_ecs_service(decrypted_data):
    """TEE calls ECS service with decrypted data"""
    
    # Create mTLS session
    session = requests.Session()
    session.verify = CA_CERT  # Verify ECS server certificate
    session.cert = (CLIENT_CERT, CLIENT_KEY)  # TEE client certificate
    
    # Send decrypted data to ECS
    response = session.post(
        f"{ECS_URL}/process",
        json=decrypted_data,
        headers={'Content-Type': 'application/json'}
    )
    
    return response.json()

# In TEE Gateway handler
def handle_external_request(encrypted_request):
    # 1. Decrypt incoming request
    decrypted_data = decrypt(encrypted_request)
    
    # 2. Call ECS service
    processed_result = call_ecs_service(decrypted_data)
    
    # 3. Encrypt result
    encrypted_response = encrypt(processed_result)
    
    # 4. Return to external client
    return encrypted_response
```

## Complete Workflow

```
1. External Client
   └─> Sends encrypted request to TEE Gateway
       (HTTPS/mTLS)

2. TEE Gateway
   ├─> Receives encrypted request
   ├─> Decrypts sensitive data
   ├─> Calls ECS service (mTLS as client)
   │   └─> Sends: decrypted_data
   │
   ├─> Receives processed result from ECS
   ├─> Encrypts result
   └─> Returns encrypted response to client

3. ECS Processing Service
   ├─> Receives decrypted data from TEE
   ├─> Processes data (business logic)
   └─> Returns processed result to TEE
```

## Key Points

1. **Dual Role for TEE**:
   - Server: Receives external requests (Gateway)
   - Client: Connects to ECS (Processing)

2. **Dual Role for ECS**:
   - Server: Accepts TEE connections (Processing)
   - Never directly exposed to external clients

3. **Certificate Management**:
   - ECS needs **server certificates** (to accept TEE connections)
   - TEE needs **client certificates** (to connect to ECS)
   - Both use same CA for verification

4. **Security**:
   - External → TEE: Encrypted (sensitive data)
   - TEE → ECS: mTLS (decrypted, but authenticated)
   - ECS → TEE: mTLS (processed result)
   - TEE → External: Encrypted (sensitive result)

5. **Data Flow**:
   - Sensitive data is **only decrypted inside TEE**
   - ECS processes decrypted data but never sees encrypted form
   - Results are encrypted by TEE before returning

## Configuration Summary

| Component | Role (External→TEE) | Role (TEE→ECS) | Certificates Needed |
|-----------|---------------------|----------------|---------------------|
| **TEE** | Server | Client | Server cert (for Gateway)<br>Client cert (for ECS) |
| **ECS** | N/A | Server | Server cert (for TEE) |

## Next Steps

1. Configure ECS with server certificates (this module)
2. Configure TEE with client certificates (Enclave deployment)
3. Deploy ECS service that listens for TEE connections
4. Update TEE Gateway to call ECS service
5. Test end-to-end flow

