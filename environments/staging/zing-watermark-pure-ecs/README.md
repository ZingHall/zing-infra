# Zing Watermark Pure ECS Cluster

This module creates a pure ECS cluster in `ap-northeast-1` using Fargate capacity providers (no EC2 instances).

## Features

- ECS cluster with Fargate and Fargate Spot capacity providers
- Container Insights enabled for monitoring
- Cost-optimized capacity provider strategy (prefers Fargate Spot)
- Deployed in `ap-northeast-1` region
- mTLS certificate configuration for TEE connectivity

## Usage

### Initialize Terraform

```bash
cd zing-infra/environments/staging/zing-watermark-pure-ecs
terraform init
```

### Plan

```bash
terraform plan
```

### Apply

```bash
terraform apply
```

## Configuration

The cluster is configured with:
- **Name**: `zing-watermark-pure-ecs`
- **Region**: `ap-northeast-1`
- **Capacity Providers**: FARGATE, FARGATE_SPOT
- **Container Insights**: Enabled
- **Default Strategy**: Prefers FARGATE_SPOT (weight: 4) with FARGATE fallback (weight: 1, base: 1)

## Outputs

- `cluster_id`: ECS cluster ID
- `cluster_arn`: ECS cluster ARN
- `cluster_name`: ECS cluster name
- `vpc_id`: VPC ID for service deployment
- `private_subnet_ids`: Private subnet IDs
- `public_subnet_ids`: Public subnet IDs
- `mtls_secret_arn`: ARN of the mTLS certificate secret (for use in ECS task definitions)

## mTLS Configuration

This cluster is configured to support mTLS connections with TEE (Trusted Execution Environment).

### Certificates

The mTLS certificates are automatically loaded from `../zing-watermark/certs/ecs-server-cert.json`, which contains:
- `server_cert`: ECS server certificate
- `server_key`: ECS server private key
- `ca_cert`: CA certificate for verification

### Using mTLS in ECS Services

When deploying services to this cluster, you can use the mTLS secret in your task definition:

```hcl
# In your ECS service task definition
secrets = [
  {
    name      = "MTLS_SERVER_CERT"
    valueFrom = module.ecs_cluster.mtls_secret_arn
  }
]
```

The secret contains a JSON object with `server_cert`, `server_key`, and `ca_cert` fields that your application can use to establish mTLS connections with TEE.

## Deploying Services

To deploy services to this cluster, use the `ecs-service` module:

```hcl
module "my_service" {
  source = "../../../modules/aws/ecs-service"

  name       = "my-service"
  cluster_id = module.ecs_cluster.cluster_id
  
  # ... other service configuration
}
```

## Cost Optimization

This cluster uses Fargate Spot by default, which can save up to 70% compared to regular Fargate. The strategy ensures at least 1 task runs on regular Fargate for stability.

