# HTTPS ALB - Usage Examples

## Example 1: Single API Service

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
    }
  ]

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

  tags = var.tags
}
```

## Example 2: Multiple Microservices

```hcl
module "alb" {
  source = "../../../modules/aws/https-alb"

  name       = "prod"
  vpc_id     = var.vpc_id
  subnet_ids = var.public_subnet_ids

  certificate_arn             = var.primary_cert_arn
  additional_certificate_arns = [var.api_cert_arn]

  services = [
    {
      name         = "web"
      port         = 3000
      host_headers = ["www.example.com", "example.com"]
      priority     = 100
      health_check_path    = "/health"
      stickiness_enabled   = true
      stickiness_duration  = 3600
    },
    {
      name         = "api"
      port         = 8080
      host_headers = ["api.example.com"]
      priority     = 101
      health_check_path    = "/api/health"
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

  tags = {
    Environment = "production"
  }
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
  desired_count      = 3

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
  desired_count      = 5

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

## Example 3: Complete Production Setup

```hcl
# 1. Create ECS Cluster
module "cluster" {
  source = "../../../modules/aws/ecs-cluster"

  name                       = "prod-services"
  container_insights_enabled = true

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

  tags = local.tags
}

# 2. Create ALB with multiple services
module "alb" {
  source = "../../../modules/aws/https-alb"

  name       = "prod"
  vpc_id     = var.vpc_id
  subnet_ids = var.public_subnet_ids

  certificate_arn             = var.wildcard_cert_arn
  additional_certificate_arns = []

  # Enable access logging
  access_log_bucket = aws_s3_bucket.alb_logs.bucket
  access_log_prefix = "prod-alb/"

  # Latest TLS policy
  ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  services = [
    {
      name         = "api"
      port         = 8080
      host_headers = ["api.example.com"]
      priority     = 100

      health_check_path                = "/api/v1/health"
      health_check_matcher             = "200"
      health_check_interval            = 15
      health_check_timeout             = 3
      health_check_healthy_threshold   = 2
      health_check_unhealthy_threshold = 3

      deregistration_delay = 15
    },
    {
      name         = "web"
      port         = 3000
      host_headers = ["www.example.com", "example.com"]
      priority     = 101

      health_check_path = "/health"

      stickiness_enabled  = true
      stickiness_duration = 3600
    },
    {
      name         = "worker-api"
      port         = 8081
      host_headers = ["worker.example.com"]
      priority     = 102

      health_check_path     = "/health"
      health_check_interval = 60
      deregistration_delay  = 60
    }
  ]

  tags = local.tags
}

# 3. Create ECS Services
module "api_service" {
  source = "../../../modules/aws/ecs-service"

  name = "api"

  cluster_id            = module.cluster.cluster_id
  alb_security_group_id = module.alb.alb_security_group_id
  target_group_arn      = module.alb.target_group_arns["api"]

  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids

  container_port = 8080
  desired_count  = 5

  task_cpu    = 512
  task_memory = 1024

  tags = local.tags
}

module "web_service" {
  source = "../../../modules/aws/ecs-service"

  name = "web"

  cluster_id            = module.cluster.cluster_id
  alb_security_group_id = module.alb.alb_security_group_id
  target_group_arn      = module.alb.target_group_arns["web"]

  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids

  container_port = 3000
  desired_count  = 3

  task_cpu    = 256
  task_memory = 512

  tags = local.tags
}

module "worker_api_service" {
  source = "../../../modules/aws/ecs-service"

  name = "worker-api"

  cluster_id            = module.cluster.cluster_id
  alb_security_group_id = module.alb.alb_security_group_id
  target_group_arn      = module.alb.target_group_arns["worker-api"]

  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids

  container_port = 8081
  desired_count  = 2

  task_cpu    = 1024
  task_memory = 2048

  tags = local.tags
}

# 4. DNS Records
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

resource "aws_route53_record" "web_root" {
  zone_id = var.hosted_zone_id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "worker" {
  zone_id = var.hosted_zone_id
  name    = "worker.example.com"
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

# 5. S3 Bucket for ALB Logs
resource "aws_s3_bucket" "alb_logs" {
  bucket = "my-alb-logs-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_elb_service_account.main.id}:root"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/*"
      }
    ]
  })
}

data "aws_elb_service_account" "main" {}
data "aws_caller_identity" "current" {}
```

## Example 4: Internal ALB for Microservices

```hcl
module "internal_alb" {
  source = "../../../modules/aws/https-alb"

  name     = "internal"
  vpc_id   = var.vpc_id
  internal = true # Internal ALB

  subnet_ids      = var.private_subnet_ids
  certificate_arn = var.internal_cert_arn

  # Only allow from VPC
  ingress_cidr_blocks = [var.vpc_cidr]

  # No HTTP redirect for internal
  http_redirect = false

  services = [
    {
      name         = "auth-service"
      port         = 8080
      host_headers = ["auth.internal"]
      priority     = 100
    },
    {
      name         = "data-service"
      port         = 8081
      host_headers = ["data.internal"]
      priority     = 101
    }
  ]

  tags = {
    Environment = "production"
    Type        = "internal"
  }
}
```

## Example 5: Development Environment

```hcl
module "dev_alb" {
  source = "../../../modules/aws/https-alb"

  name       = "dev"
  vpc_id     = var.vpc_id
  subnet_ids = var.public_subnet_ids

  certificate_arn = var.dev_cert_arn

  services = [
    {
      name         = "api-dev"
      port         = 8080
      host_headers = ["api-dev.example.com"]
      priority     = 100

      # More lenient health checks for dev
      health_check_interval            = 60
      health_check_unhealthy_threshold = 5
    },
    {
      name         = "web-dev"
      port         = 3000
      host_headers = ["dev.example.com"]
      priority     = 101
    }
  ]

  tags = {
    Environment = "development"
  }
}
```

## Example 6: Adding a New Service

```hcl
# Existing configuration
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
    },
    {
      name         = "web"
      port         = 3000
      host_headers = ["www.example.com"]
      priority     = 101
    },
    # NEW: Adding a new service
    {
      name         = "mobile-api"
      port         = 8082
      host_headers = ["mobile-api.example.com"]
      priority     = 102
      health_check_path = "/mobile/health"
    }
  ]

  tags = var.tags
}

# Create the new ECS service
module "mobile_api_service" {
  source = "../../../modules/aws/ecs-service"

  name                  = "mobile-api"
  cluster_id            = module.cluster.cluster_id
  alb_security_group_id = module.alb.alb_security_group_id
  target_group_arn      = module.alb.target_group_arns["mobile-api"]

  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids
  container_port     = 8082

  tags = var.tags
}
```

## Comparison: Before vs After

### Before (Using Separate Modules)

```hcl
# Create ALB
module "alb" {
  source          = "../../../modules/aws/alb"
  name            = "prod"
  vpc_id          = var.vpc_id
  subnet_ids      = var.public_subnet_ids
  certificate_arn = var.cert_arn
}

# Create target group for API
module "api_tg" {
  source       = "../../../modules/aws/alb-target-group"
  name         = "api"
  vpc_id       = var.vpc_id
  listener_arn = module.alb.https_listener_arn
  port         = 8080
  host_headers = ["api.example.com"]
  priority     = 100
}

# Create target group for Web
module "web_tg" {
  source       = "../../../modules/aws/alb-target-group"
  name         = "web"
  vpc_id       = var.vpc_id
  listener_arn = module.alb.https_listener_arn
  port         = 3000
  host_headers = ["www.example.com"]
  priority     = 101
}

# Total: 3 module blocks
```

### After (Using Combined Module)

```hcl
# Create ALB with all services
module "alb" {
  source          = "../../../modules/aws/https-server-alb"
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

# Total: 1 module block ✅
```

**Benefits:**
- ✅ 67% less code
- ✅ Easier to maintain
- ✅ Single source of truth
- ✅ Automatic validation
- ✅ Cleaner structure

## Tips & Best Practices

### Priority Assignment

Leave gaps between priorities for easy insertion:
```hcl
services = [
  { name = "api",   priority = 100 },  # Leave gap
  { name = "web",   priority = 110 },  # Leave gap
  { name = "admin", priority = 120 },
]
```

### Health Check Optimization

For fast-response APIs:
```hcl
{
  health_check_interval            = 15
  health_check_timeout             = 3
  health_check_healthy_threshold   = 2
  health_check_unhealthy_threshold = 2
  deregistration_delay             = 15
}
```

For slow-starting services:
```hcl
{
  health_check_interval            = 60
  health_check_timeout             = 10
  health_check_healthy_threshold   = 3
  health_check_unhealthy_threshold = 5
  deregistration_delay             = 60
}
```

### Session Stickiness

Only enable for stateful applications:
```hcl
{
  stickiness_enabled  = true
  stickiness_duration = 3600  # 1 hour
}
```

### Multi-Domain Setup

Use wildcard certificate + specific domains:
```hcl
certificate_arn = var.wildcard_cert_arn  # *.example.com

services = [
  { host_headers = ["api.example.com"] },
  { host_headers = ["web.example.com"] },
  { host_headers = ["admin.example.com"] },
]
```

