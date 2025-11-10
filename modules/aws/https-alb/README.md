# HTTPS ALB Module

A combined module that creates an Application Load Balancer with HTTPS listener, target groups, and routing rules - specifically designed for ECS services.

## Features

- ✅ Single module creates ALB + Target Groups + Routing Rules
- ✅ HTTPS-first with automatic HTTP→HTTPS redirect
- ✅ Multi-service support (multiple target groups)
- ✅ Host-based routing (domain per service)
- ✅ Optimized for ECS Fargate (target_type = "ip")
- ✅ Configurable health checks per service
- ✅ Session stickiness support
- ✅ Multi-domain SSL certificate support

## Usage

### Single Service

```hcl
module "alb" {
  source = "../../../modules/aws/https-alb"

  name       = "prod"
  vpc_id     = var.vpc_id
  subnet_ids = var.public_subnet_ids

  certificate_arn = var.cert_arn

  services = [
    {
      name         = "api"
      port         = 8080
      host_headers = ["api.example.com"]
      priority     = 100
      health_check_path = "/api/health"
    }
  ]

  tags = var.tags
}

# Use with ECS service
module "api_service" {
  source = "../../../modules/aws/ecs-service"

  name = "api"

  cluster_id            = module.cluster.cluster_id
  alb_security_group_id = module.alb.alb_security_group_id
  target_group_arn      = module.alb.target_group_arns["api"]

  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids

  container_port = 8080
  desired_count  = 3

  tags = var.tags
}
```

### Multiple Services

```hcl
module "alb" {
  source = "../../../modules/aws/https-alb"

  name       = "prod"
  vpc_id     = var.vpc_id
  subnet_ids = var.public_subnet_ids

  certificate_arn = var.primary_cert_arn
  additional_certificate_arns = [
    var.api_cert_arn,
    var.admin_cert_arn
  ]

  services = [
    {
      name                 = "web"
      port                 = 3000
      host_headers         = ["www.example.com", "example.com"]
      priority             = 100
      health_check_path    = "/health"
      stickiness_enabled   = true
    },
    {
      name         = "api"
      port         = 8080
      host_headers = ["api.example.com"]
      priority     = 101
      health_check_path = "/api/health"
      health_check_matcher = "200"
    },
    {
      name         = "admin"
      port         = 3000
      host_headers = ["admin.example.com"]
      priority     = 102
      health_check_path = "/admin/health"
    }
  ]

  tags = var.tags
}

# Create ECS services
module "web_service" {
  source = "../../../modules/aws/ecs-service"

  name                  = "web"
  cluster_id            = module.cluster.cluster_id
  alb_security_group_id = module.alb.alb_security_group_id
  target_group_arn      = module.alb.target_group_arns["web"]

  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids
  container_port     = 3000
  desired_count      = 2

  tags = var.tags
}

module "api_service" {
  source = "../../../modules/aws/ecs-service"

  name                  = "api"
  cluster_id            = module.cluster.cluster_id
  alb_security_group_id = module.alb.alb_security_group_id
  target_group_arn      = module.alb.target_group_arns["api"]

  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids
  container_port     = 8080
  desired_count      = 3

  tags = var.tags
}

module "admin_service" {
  source = "../../../modules/aws/ecs-service"

  name                  = "admin"
  cluster_id            = module.cluster.cluster_id
  alb_security_group_id = module.alb.alb_security_group_id
  target_group_arn      = module.alb.target_group_arns["admin"]

  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids
  container_port     = 3000
  desired_count      = 1

  tags = var.tags
}
```

### Complete Example with All Features

```hcl
module "alb" {
  source = "../../../modules/aws/https-alb"

  name     = "prod"
  vpc_id   = var.vpc_id
  subnet_ids = var.public_subnet_ids

  certificate_arn             = var.cert_arn
  additional_certificate_arns = var.additional_certs

  # Restrict access (optional)
  ingress_cidr_blocks = ["0.0.0.0/0"]

  # Enable access logging
  access_log_bucket = "my-alb-logs"
  access_log_prefix = "prod-alb/"

  # Use latest TLS policy
  ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  services = [
    {
      name         = "api"
      port         = 8080
      host_headers = ["api.example.com"]
      priority     = 100

      # Custom health check
      health_check_path                = "/api/v1/health"
      health_check_matcher             = "200"
      health_check_interval            = 15
      health_check_timeout             = 3
      health_check_healthy_threshold   = 2
      health_check_unhealthy_threshold = 3

      # Faster deregistration
      deregistration_delay = 15

      # Enable session stickiness
      stickiness_enabled  = true
      stickiness_duration = 3600
    },
    {
      name         = "web"
      port         = 3000
      host_headers = ["www.example.com", "example.com"]
      priority     = 101

      health_check_path = "/health"
    }
  ]

  tags = {
    Environment = "production"
    Team        = "platform"
  }
}
```

## Inputs

### Required

| Name | Description | Type |
|------|-------------|------|
| name | Name prefix for ALB | string |
| vpc_id | VPC ID | string |
| subnet_ids | Subnet IDs (public) | list(string) |
| certificate_arn | Primary SSL certificate ARN | string |
| services | List of services configuration | list(object) |

### Service Object

| Field | Description | Type | Default | Required |
|-------|-------------|------|---------|----------|
| name | Service name | string | - | yes |
| port | Container port | number | - | yes |
| host_headers | Domain names | list(string) | - | yes |
| priority | Rule priority | number | - | yes |
| health_check_path | Health check path | string | "/health" | no |
| health_check_matcher | Success codes | string | "200-399" | no |
| health_check_interval | Check interval (seconds) | number | 30 | no |
| health_check_timeout | Check timeout (seconds) | number | 5 | no |
| health_check_healthy_threshold | Healthy threshold | number | 2 | no |
| health_check_unhealthy_threshold | Unhealthy threshold | number | 2 | no |
| deregistration_delay | Drain time (seconds) | number | 30 | no |
| stickiness_enabled | Enable session stickiness | bool | false | no |
| stickiness_duration | Stickiness duration (seconds) | number | 86400 | no |

### Optional

| Name | Description | Type | Default |
|------|-------------|------|---------|
| internal | Internal ALB | bool | false |
| ingress_cidr_blocks | Allowed IPs | list(string) | ["0.0.0.0/0"] |
| http_redirect | HTTP→HTTPS redirect | bool | true |
| ssl_policy | TLS policy | string | "ELBSecurityPolicy-TLS13-1-2-2021-06" |
| additional_certificate_arns | Additional certs | list(string) | [] |
| access_log_bucket | S3 bucket for logs | string | "" |
| access_log_prefix | S3 prefix | string | "" |
| tags | Resource tags | map(string) | {} |

## Outputs

| Name | Description |
|------|-------------|
| alb_id | ALB ID |
| alb_arn | ALB ARN |
| alb_dns_name | ALB DNS name |
| alb_zone_id | ALB Zone ID |
| alb_security_group_id | ALB security group ID |
| https_listener_arn | HTTPS listener ARN |
| target_group_arns | Map of service→target group ARN |
| target_group_names | Map of service→target group name |
| service_endpoints | Map of service→HTTPS endpoint |

## Benefits

### Simplified Usage

**Before (3 separate modules):**
```hcl
module "alb" { ... }
module "api_tg" { ... }
module "web_tg" { ... }
```

**After (1 module):**
```hcl
module "alb" {
  services = [
    { name = "api", ... },
    { name = "web", ... }
  ]
}
```

### Automatic Configuration

- ✅ Target groups configured for ECS Fargate (ip targets)
- ✅ Health checks pre-configured with sensible defaults
- ✅ Listener rules automatically created
- ✅ Priorities validated (no conflicts)
- ✅ Service names validated (no duplicates)

### Built for ECS

- Optimized defaults for container workloads
- Fast deregistration for quick deployments
- Proper health check settings
- Session stickiness support

## Best Practices

1. **Priority Assignment**: Leave gaps (100, 110, 120) for easy insertions
2. **Health Checks**: Use dedicated health endpoints
3. **Stickiness**: Enable only when needed (stateful apps)
4. **TLS Policy**: Use latest policy for security
5. **Access Logs**: Enable for production environments

## Example: Complete Setup

```hcl
# 1. Create cluster
module "cluster" {
  source = "../../../modules/aws/ecs-cluster"
  name   = "prod"
  container_insights_enabled = true
}

# 2. Create ALB with services
module "alb" {
  source = "../../../modules/aws/https-alb"

  name            = "prod"
  vpc_id          = var.vpc_id
  subnet_ids      = var.public_subnet_ids
  certificate_arn = var.cert_arn

  services = [
    {
      name         = "api"
      port         = 8080
      host_headers = ["api.example.com"]
      priority     = 100
    },
    {
      name         = "web"
      port         = 3000
      host_headers = ["www.example.com"]
      priority     = 101
    }
  ]
}

# 3. Create ECS services
module "api" {
  source = "../../../modules/aws/ecs-service"

  name                  = "api"
  cluster_id            = module.cluster.cluster_id
  alb_security_group_id = module.alb.alb_security_group_id
  target_group_arn      = module.alb.target_group_arns["api"]

  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids
  container_port     = 8080
}

module "web" {
  source = "../../../modules/aws/ecs-service"

  name                  = "web"
  cluster_id            = module.cluster.cluster_id
  alb_security_group_id = module.alb.alb_security_group_id
  target_group_arn      = module.alb.target_group_arns["web"]

  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids
  container_port     = 3000
}

# 4. DNS records
resource "aws_route53_record" "api" {
  zone_id = var.hosted_zone_id
  name    = "api.example.com"
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "web" {
  zone_id = var.hosted_zone_id
  name    = "www.example.com"
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}
```

## Troubleshooting

**Issue**: Service priority conflicts  
**Solution**: Ensure each service has a unique priority number

**Issue**: Target group unhealthy  
**Solution**: Check health_check_path returns 200-399

**Issue**: 404 errors  
**Solution**: Verify host_headers match your domain names

## Related Modules

- **`ecs-cluster`** - Create ECS clusters
- **`ecs-service`** - Create ECS services

## Migration from Separate Modules

If you're currently using separate `alb` and `alb-target-group` modules:

1. Note your current ALB and target group configurations
2. Replace with this module
3. Update service references to use `target_group_arns` output
4. Run `terraform plan` to verify changes
5. Apply incrementally

This module is **backward compatible** - your services will continue working with new target groups.

