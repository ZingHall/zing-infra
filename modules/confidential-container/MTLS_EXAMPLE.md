# mTLS Configuration Example

Complete example of configuring mTLS connectivity between Confidential Container ECS cluster and Nitro Enclave.

## Overview

This example shows how to:
1. Create mTLS certificates in Secrets Manager
2. Configure security groups for Enclave connectivity
3. Deploy ECS cluster with mTLS support
4. Use mTLS in container applications

## Architecture: Server vs Client Roles

**Important**: In this mTLS setup:
- **Nitro Enclave = Server** (服务端)
  - Listens on port 3000 for incoming connections
  - Uses server certificate for mTLS
  - Waits for client connections
  
- **Confidential Container ECS = Client** (客户端)
  - Initiates connections to Enclave
  - Uses client certificate (`client.crt`, `client.key`) for mTLS
  - Connects to Enclave endpoints

```
┌─────────────────────────┐         mTLS          ┌──────────────────────┐
│  ECS Confidential       │  ──────────────────>  │  Nitro Enclave       │
│  Container (Client)     │   (client cert)      │  (Server)            │
│                         │                      │  (server cert)       │
│  - client.crt           │                      │  - Listens on :3000  │
│  - client.key           │                      │  - Validates client │
│  - ca.crt               │                      │    certificate       │
└─────────────────────────┘                      └──────────────────────┘
```

The certificates stored in Secrets Manager are **client certificates** for the ECS containers to authenticate themselves when connecting to the Enclave server.

## Step 1: Prepare mTLS Certificates

### Certificate Roles

In mTLS, both sides need certificates:
- **Enclave (Server)**: Needs server certificate (configured separately in Enclave)
- **ECS (Client)**: Needs client certificate (stored in Secrets Manager, downloaded to ECS instances)

This step creates the **client certificate** for ECS containers.

### Generate Client Certificates for ECS

```bash
# Create CA (if not already exists)
openssl genrsa -out ca.key 4096
openssl req -new -x509 -days 365 -key ca.key -out ca.crt \
  -subj "/CN=Enclave-CA"

# Create client certificate for ECS containers
openssl genrsa -out client.key 4096
openssl req -new -key client.key -out client.csr \
  -subj "/CN=ECS-Client"

# Sign client certificate with CA
openssl x509 -req -days 365 -in client.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out client.crt
```

**Note**: The Enclave server certificate should be configured separately in your Enclave deployment. The CA certificate (`ca.crt`) should be used by both:
- ECS clients to verify Enclave server certificate
- Enclave server to verify ECS client certificates

### Store Client Certificates in Secrets Manager

```hcl
# Create secret for ECS client certificates
# These are CLIENT certificates used by ECS containers to authenticate to Enclave
resource "aws_secretsmanager_secret" "mtls_cert" {
  name        = "confidential-cluster-mtls-cert"
  description = "Client mTLS certificates for ECS containers (client role)"
  
  tags = {
    Purpose = "mTLS"
    Cluster = "confidential-cluster"
    Role    = "client"  # ECS acts as client
  }
}

# Store client certificates as JSON
resource "aws_secretsmanager_secret_version" "mtls_cert" {
  secret_id = aws_secretsmanager_secret.mtls_cert.id
  
  secret_string = jsonencode({
    client_cert = file("${path.module}/certs/client.crt")  # ECS client certificate
    client_key  = file("${path.module}/certs/client.key")  # ECS client private key
    ca_cert     = file("${path.module}/certs/ca.crt")      # CA to verify Enclave server cert
  })
}
```

**Important**: 
- These are **client certificates** for ECS containers
- The Enclave server should have its own server certificate configured
- Both should be signed by the same CA (or use the same CA certificate for verification)

## Step 2: Get Enclave Security Group

```hcl
# Get existing Enclave security group
data "aws_security_group" "enclave" {
  name = "nautilus-watermark-staging-enclave-sg"
  
  # Or use ID if you know it
  # id = "sg-0123456789abcdef0"
}
```

## Step 3: Configure ECS Cluster with mTLS

```hcl
module "confidential_cluster" {
  source = "../../modules/confidential-container"

  name    = "confidential-cluster"
  vpc_id  = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids

  instance_type = "m6a.large"
  ami_os         = "amazon-linux-2023"

  min_size         = 2
  max_size         = 5
  desired_capacity = 2

  # Enable mTLS connectivity
  enable_enclave_mtls = true
  
  # Enclave security group for network rules
  enclave_security_group_ids = [
    data.aws_security_group.enclave.id
  ]
  
  # Enclave endpoints (from ALB or direct instance IPs)
  enclave_endpoints = [
    "enclave-internal.example.com:3000",
    "10.0.1.100:3000"  # Direct IP if using private IPs
  ]
  
  # mTLS certificate secrets
  mtls_certificate_secrets_arns = [
    aws_secretsmanager_secret.mtls_cert.arn
  ]
  
  # Optional: Custom certificate path
  mtls_certificate_path = "/etc/ecs/mtls"

  container_insights_enabled = true
  enable_managed_scaling     = true

  tags = {
    Environment = "production"
    Team        = "security"
    Purpose     = "confidential-computing"
  }
}
```

## Step 4: Configure Enclave Security Group

Ensure the Enclave security group allows inbound from ECS security group:

```hcl
# Allow ECS instances to connect to Enclave
resource "aws_security_group_rule" "enclave_ingress_from_ecs" {
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  source_security_group_id = module.confidential_cluster.security_group_id
  security_group_id         = data.aws_security_group.enclave.id
  description              = "Allow mTLS from ECS confidential cluster"
}
```

## Step 5: Use mTLS in Container Applications

### Python Example

```python
import ssl
import requests
import os

# Certificate paths (mounted from host)
CERT_DIR = "/etc/ecs/mtls"
CLIENT_CERT = f"{CERT_DIR}/client.crt"
CLIENT_KEY = f"{CERT_DIR}/client.key"
CA_CERT = f"{CERT_DIR}/ca.crt"

# Enclave endpoint
ENCLAVE_URL = os.getenv("ENCLAVE_ENDPOINT", "https://enclave.example.com:3000")

def create_mtls_session():
    """Create requests session with mTLS"""
    session = requests.Session()
    
    # Configure SSL context
    session.verify = CA_CERT
    session.cert = (CLIENT_CERT, CLIENT_KEY)
    
    return session

# Use mTLS session
session = create_mtls_session()
response = session.get(f"{ENCLAVE_URL}/api/watermark")
print(response.json())
```

### Node.js Example

```javascript
const https = require('https');
const fs = require('fs');

const certDir = '/etc/ecs/mtls';
const options = {
  cert: fs.readFileSync(`${certDir}/client.crt`),
  key: fs.readFileSync(`${certDir}/client.key`),
  ca: fs.readFileSync(`${certDir}/ca.crt`),
  hostname: 'enclave.example.com',
  port: 3000,
  path: '/api/watermark',
  method: 'GET'
};

const req = https.request(options, (res) => {
  let data = '';
  res.on('data', (chunk) => {
    data += chunk;
  });
  res.on('end', () => {
    console.log(JSON.parse(data));
  });
});

req.on('error', (e) => {
  console.error(`Problem with request: ${e.message}`);
});

req.end();
```

### Go Example

```go
package main

import (
    "crypto/tls"
    "crypto/x509"
    "io/ioutil"
    "net/http"
    "os"
)

func createMTLSClient() (*http.Client, error) {
    certDir := "/etc/ecs/mtls"
    
    // Load client certificate
    cert, err := tls.LoadX509KeyPair(
        certDir+"/client.crt",
        certDir+"/client.key",
    )
    if err != nil {
        return nil, err
    }
    
    // Load CA certificate
    caCert, err := ioutil.ReadFile(certDir + "/ca.crt")
    if err != nil {
        return nil, err
    }
    
    caCertPool := x509.NewCertPool()
    caCertPool.AppendCertsFromPEM(caCert)
    
    // Configure TLS
    tlsConfig := &tls.Config{
        Certificates: []tls.Certificate{cert},
        RootCAs:      caCertPool,
    }
    
    transport := &http.Transport{
        TLSClientConfig: tlsConfig,
    }
    
    return &http.Client{Transport: transport}, nil
}

func main() {
    client, err := createMTLSClient()
    if err != nil {
        panic(err)
    }
    
    enclaveURL := os.Getenv("ENCLAVE_ENDPOINT")
    resp, err := client.Get(enclaveURL + "/api/watermark")
    if err != nil {
        panic(err)
    }
    defer resp.Body.Close()
    
    // Handle response...
}
```

## Step 6: Mount Certificates in ECS Task Definition

```json
{
  "family": "confidential-app",
  "containerDefinitions": [
    {
      "name": "app",
      "image": "your-app:latest",
      "mountPoints": [
        {
          "sourceVolume": "mtls-certs",
          "containerPath": "/etc/ecs/mtls",
          "readOnly": true
        }
      ],
      "environment": [
        {
          "name": "ENCLAVE_ENDPOINT",
          "value": "https://enclave.example.com:3000"
        }
      ]
    }
  ],
  "volumes": [
    {
      "name": "mtls-certs",
      "host": {
        "sourcePath": "/etc/ecs/mtls"
      }
    }
  ]
}
```

## Step 7: Verify mTLS Configuration

### Check Certificates on Instance

```bash
# SSH into ECS instance
aws ssm start-session --target i-0123456789abcdef0

# Check certificates
sudo ls -la /etc/ecs/mtls/
sudo cat /etc/ecs/mtls/client.crt
sudo openssl x509 -in /etc/ecs/mtls/client.crt -text -noout
```

### Test mTLS Connection

```bash
# From ECS instance
curl -v \
  --cert /etc/ecs/mtls/client.crt \
  --key /etc/ecs/mtls/client.key \
  --cacert /etc/ecs/mtls/ca.crt \
  https://enclave.example.com:3000/health
```

### Check Security Groups

```bash
# Verify ECS security group allows outbound to Enclave
aws ec2 describe-security-groups \
  --group-ids sg-ecs-id \
  --query 'SecurityGroups[0].IpPermissionsEgress'

# Verify Enclave security group allows inbound from ECS
aws ec2 describe-security-groups \
  --group-ids sg-enclave-id \
  --query 'SecurityGroups[0].IpPermissions'
```

## Troubleshooting

### Certificates Not Found

- Check IAM role has `secretsmanager:GetSecretValue` permission
- Verify secret ARN is correct
- Check secret exists in the same region
- Review `/var/log/ecs-init.log` for download errors

### Connection Refused

- Verify security group rules allow traffic
- Check Enclave is running and listening on port
- Verify endpoint URL is correct
- Check network connectivity (ping, telnet)

### Certificate Validation Failed

- Verify certificate format (PEM encoding)
- Check certificate expiration dates
- Ensure CA certificate matches Enclave's CA
- Verify certificate Common Name (CN) matches Enclave's expected client name

### Permission Denied

- Check file permissions: `chmod 600 /etc/ecs/mtls/*.key`
- Verify container has read access to certificate directory
- Check SELinux/apparmor policies if applicable

## Best Practices

1. **Certificate Rotation**: Implement automated certificate rotation
2. **Secret Management**: Use separate secrets for different environments
3. **Network Isolation**: Use private subnets and security groups
4. **Monitoring**: Monitor mTLS connection success rates
5. **Logging**: Log all mTLS connection attempts and failures
6. **Error Handling**: Implement retry logic for transient failures
7. **Certificate Validation**: Always validate certificate chains
8. **Key Management**: Never log or expose private keys

## Security Considerations

- Certificates are stored encrypted at rest in Secrets Manager
- Certificates are downloaded over HTTPS during instance startup
- File permissions restrict access to root user
- Security groups enforce network-level isolation
- mTLS provides mutual authentication (both sides verify identity)

