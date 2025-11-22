# mTLS Setup for Pure ECS Cluster

This document explains how mTLS is configured for the `zing-watermark-pure-ecs` cluster to connect with TEE (Trusted Execution Environment).

## Overview

The cluster is configured to:
- Store mTLS server certificates in AWS Secrets Manager
- Load certificates from `../zing-watermark/certs/ecs-server-cert.json`
- Make certificates available to ECS services via Secrets Manager

## Certificate Source

Certificates are automatically loaded from:
```
../zing-watermark/certs/ecs-server-cert.json
```

This file contains:
- `server_cert`: ECS server certificate (for accepting TEE connections)
- `server_key`: ECS server private key
- `ca_cert`: CA certificate for verifying TEE client certificates

## Secret Configuration

The certificates are stored in AWS Secrets Manager:
- **Secret Name**: `ecs-server-mtls-cert-pure-ecs` (if creating new) or `ecs-server-mtls-cert` (if using existing)
- **Region**: `ap-northeast-1`
- **Format**: JSON string containing all three certificate fields

## Using mTLS in ECS Services

When deploying a service to this cluster, configure the task definition to use the secret:

### Option 1: As Environment Variables (Recommended for Fargate)

```hcl
# In your ECS task definition
container_definitions = jsonencode([
  {
    name = "watermark"
    # ... other config ...
    
    secrets = [
      {
        name      = "MTLS_CERT_JSON"
        valueFrom = module.ecs_cluster.mtls_secret_arn
      }
    ]
  }
])
```

Your application can then parse the JSON to extract:
- `server_cert`
- `server_key`
- `ca_cert`

### Option 2: Using ECS Role

Ensure your ECS execution role has permissions to read the secret:

```hcl
module "ecs_role" {
  source = "../../../modules/aws/ecs-role"
  
  name                  = "my-service"
  enable_secrets_access = true
  secrets_arns          = [module.ecs_cluster.mtls_secret_arn]
  
  # ... other config ...
}
```

## Architecture

```
┌─────────────────────┐         mTLS          ┌──────────────────────┐
│  TEE Enclave        │  ──────────────────>  │  ECS Service        │
│  (Client)           │   (client cert)       │  (Server)            │
│  ap-northeast-1     │                      │  (server cert)       │
│                     │                      │  ap-northeast-1       │
└─────────────────────┘                      └──────────────────────┘
```

- **TEE Role**: Client (initiates connection to ECS)
- **ECS Role**: Server (accepts connections from TEE)
- **Protocol**: mTLS (mutual TLS authentication)

## Verification

After deployment, verify the secret exists:

```bash
aws secretsmanager describe-secret \
  --secret-id ecs-server-mtls-cert-pure-ecs \
  --region ap-northeast-1 \
  --profile zing-staging
```

Get the secret value:

```bash
aws secretsmanager get-secret-value \
  --secret-id ecs-server-mtls-cert-pure-ecs \
  --region ap-northeast-1 \
  --profile zing-staging \
  --query SecretString --output text | jq .
```

## Troubleshooting

### Certificate Not Found

If you get an error about the certificate file not found:
1. Ensure `../zing-watermark/certs/ecs-server-cert.json` exists
2. Check the file path is correct relative to the Terraform module

### Secret Access Denied

If ECS tasks can't access the secret:
1. Verify the execution role has `secretsmanager:GetSecretValue` permission
2. Check the secret ARN is correct in the task definition
3. Ensure KMS permissions if the secret is encrypted

### Connection Issues

If mTLS connections fail:
1. Verify certificates are valid and not expired
2. Check security groups allow traffic between TEE and ECS
3. Ensure the application is listening on the correct port
4. Verify certificate paths in the application code

