# ECS Cluster Module

This module creates an AWS ECS cluster with configurable capacity providers and Container Insights.

## Features

- ECS cluster creation
- Container Insights (optional)
- Capacity provider configuration (FARGATE, FARGATE_SPOT)
- CloudWatch log group (optional)
- Support for multiple services per cluster

## Usage

### Basic Cluster

```hcl
module "ecs_cluster" {
  source = "../../../modules/aws/ecs-cluster"

  name = "my-cluster"

  tags = {
    Environment = "production"
    Team        = "platform"
  }
}
```

### Cluster with Container Insights

```hcl
module "ecs_cluster" {
  source = "../../../modules/aws/ecs-cluster"

  name = "monitored-cluster"
  
  container_insights_enabled = true
  create_cloudwatch_log_group = true
  log_retention_in_days       = 30

  tags = var.tags
}
```

### Cluster with Custom Capacity Providers

```hcl
module "ecs_cluster" {
  source = "../../../modules/aws/ecs-cluster"

  name = "spot-cluster"

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  
  default_capacity_provider_strategy = [
    {
      capacity_provider = "FARGATE_SPOT"
      weight            = 4
      base              = 0
    },
    {
      capacity_provider = "FARGATE"
      weight            = 1
      base              = 1
    }
  ]

  tags = var.tags
}
```

### Multiple Services on One Cluster

```hcl
# Create one cluster
module "shared_cluster" {
  source = "../../../modules/aws/ecs-cluster"

  name                        = "services"
  container_insights_enabled  = true

  tags = var.tags
}

# Deploy multiple services to the same cluster
module "api_service" {
  source = "../../../modules/aws/ecs-service"

  name               = "api"
  cluster_id         = module.shared_cluster.cluster_id
  create_cluster     = false
  
  # ... other service configuration
}

module "web_service" {
  source = "../../../modules/aws/ecs-service"

  name           = "web"
  cluster_id     = module.shared_cluster.cluster_id
  create_cluster = false
  
  # ... other service configuration
}

module "worker_service" {
  source = "../../../modules/aws/ecs-service"

  name           = "worker"
  cluster_id     = module.shared_cluster.cluster_id
  create_cluster = false
  
  # ... other service configuration
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name of the ECS cluster | string | - | yes |
| container_insights_enabled | Enable Container Insights | bool | false | no |
| capacity_providers | List of capacity providers | list(string) | ["FARGATE", "FARGATE_SPOT"] | no |
| default_capacity_provider_strategy | Default capacity provider strategy | list(object) | [] | no |
| create_cloudwatch_log_group | Create CloudWatch log group | bool | false | no |
| log_retention_in_days | Log retention in days | number | 180 | no |
| tags | Tags to apply | map(string) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster_id | ECS cluster ID |
| cluster_arn | ECS cluster ARN |
| cluster_name | ECS cluster name |
| cloudwatch_log_group_name | CloudWatch log group name |
| cloudwatch_log_group_arn | CloudWatch log group ARN |

## Cost Optimization with Fargate Spot

Using FARGATE_SPOT can save up to 70% compared to FARGATE:

```hcl
module "cost_optimized_cluster" {
  source = "../../../modules/aws/ecs-cluster"

  name = "cost-optimized"

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  
  # Prefer FARGATE_SPOT with FARGATE as fallback
  default_capacity_provider_strategy = [
    {
      capacity_provider = "FARGATE_SPOT"
      weight            = 100  # Prefer SPOT
      base              = 0
    },
    {
      capacity_provider = "FARGATE"
      weight            = 0
      base              = 1    # At least 1 on FARGATE for stability
    }
  ]

  tags = var.tags
}
```

## Container Insights

Container Insights provides:
- CPU and memory utilization metrics
- Task-level metrics
- Service-level metrics
- Network metrics

**Cost:** Additional CloudWatch charges apply (~$0.30 per vCPU-hour)

Enable only for production clusters or when detailed monitoring is needed.

## Best Practices

1. **Naming:** Use descriptive cluster names (e.g., `prod-services`, `staging-cluster`)
2. **Cost:** Use FARGATE_SPOT for non-critical workloads
3. **Monitoring:** Enable Container Insights for production
4. **Organization:** One cluster per environment or per team
5. **Capacity:** Start with default capacity providers, adjust based on needs

## Examples

See usage examples above for common configurations.

