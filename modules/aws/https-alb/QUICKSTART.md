# HTTPS ALB - Quick Start

## 5-Minute Setup

### Step 1: Create the ALB

```hcl
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

  tags = {
    Environment = "production"
  }
}
```

### Step 2: Create ECS Services

```hcl
# API Service
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

# Web Service
module "web_service" {
  source = "../../../modules/aws/ecs-service"

  name                  = "web"
  cluster_id            = module.cluster.cluster_id
  alb_security_group_id = module.alb.alb_security_group_id
  target_group_arn      = module.alb.target_group_arns["web"]

  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids
  container_port     = 3000

  tags = var.tags
}
```

### Step 3: DNS Records

```hcl
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

## Complete Stack (Copy & Paste)

```hcl
# ============================================
# Complete ECS + ALB Setup
# ============================================

# 1. ECS Cluster
module "cluster" {
  source = "../../../modules/aws/ecs-cluster"

  name                       = "prod-cluster"
  container_insights_enabled = true

  tags = local.tags
}

# 2. ALB with Services
module "alb" {
  source = "../../../modules/aws/https-alb"

  name            = "prod"
  vpc_id          = var.vpc_id
  subnet_ids      = var.public_subnet_ids
  certificate_arn = var.wildcard_cert_arn

  services = [
    {
      name                 = "api"
      port                 = 8080
      host_headers         = ["api.example.com"]
      priority             = 100
      health_check_path    = "/api/health"
      deregistration_delay = 15
    },
    {
      name                 = "web"
      port                 = 3000
      host_headers         = ["www.example.com", "example.com"]
      priority             = 101
      health_check_path    = "/health"
      stickiness_enabled   = true
    }
  ]

  tags = local.tags
}

# 3. ECS Services
module "api_service" {
  source = "../../../modules/aws/ecs-service"

  name                  = "api"
  cluster_id            = module.cluster.cluster_id
  alb_security_group_id = module.alb.alb_security_group_id
  target_group_arn      = module.alb.target_group_arns["api"]

  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids

  container_port = 8080
  desired_count  = 3
  task_cpu       = 512
  task_memory    = 1024

  tags = local.tags
}

module "web_service" {
  source = "../../../modules/aws/ecs-service"

  name                  = "web"
  cluster_id            = module.cluster.cluster_id
  alb_security_group_id = module.alb.alb_security_group_id
  target_group_arn      = module.alb.target_group_arns["web"]

  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids

  container_port = 3000
  desired_count  = 2
  task_cpu       = 256
  task_memory    = 512

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

# 5. Outputs
output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.alb.alb_dns_name
}

output "service_endpoints" {
  description = "Service endpoints"
  value       = module.alb.service_endpoints
}

output "cluster_name" {
  description = "ECS cluster name"
  value       = module.cluster.cluster_name
}

# Local variables
locals {
  tags = {
    Environment = "production"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}
```

## Variables (variables.tf)

```hcl
variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for ALB"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS services"
  type        = list(string)
}

variable "wildcard_cert_arn" {
  description = "Wildcard SSL certificate ARN"
  type        = string
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
}
```

## Common Patterns

### Add New Service

```hcl
# 1. Add to ALB services list
services = [
  { name = "api",   priority = 100 },
  { name = "web",   priority = 101 },
  { name = "admin", priority = 102 },  # NEW
]

# 2. Create ECS service
module "admin_service" {
  source = "../../../modules/aws/ecs-service"

  name                  = "admin"
  cluster_id            = module.cluster.cluster_id
  alb_security_group_id = module.alb.alb_security_group_id
  target_group_arn      = module.alb.target_group_arns["admin"]

  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids
  container_port     = 3000
}

# 3. Add DNS record
resource "aws_route53_record" "admin" {
  zone_id = var.hosted_zone_id
  name    = "admin.example.com"
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}
```

### Multiple Domains per Service

```hcl
{
  name         = "web"
  port         = 3000
  host_headers = [
    "www.example.com",
    "example.com",
    "app.example.com"
  ]
  priority = 100
}
```

### Custom Health Check

```hcl
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
  
  # Fast draining
  deregistration_delay = 15
}
```

### Session Stickiness

```hcl
{
  name         = "web"
  port         = 3000
  host_headers = ["www.example.com"]
  priority     = 100
  
  # Enable stickiness
  stickiness_enabled  = true
  stickiness_duration = 3600  # 1 hour
}
```

## Deployment Commands

```bash
# Initialize
terraform init

# Plan
terraform plan

# Apply
terraform apply

# Check ALB
terraform output alb_dns_name

# Check service endpoints
terraform output service_endpoints
```

## Validation Checklist

Before applying:

- [ ] Service names are unique
- [ ] Service priorities are unique (no conflicts)
- [ ] SSL certificate ARN is valid
- [ ] Health check paths exist in your app
- [ ] Container ports match your Docker config
- [ ] VPC has internet gateway (for public ALB)
- [ ] Private subnets have NAT gateway (for ECS)

## Architecture

```
┌─────────────────────────────────────────┐
│         Route 53 DNS                    │
│  api.example.com → ALB                  │
│  www.example.com → ALB                  │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  Application Load Balancer (ALB)        │
│  ┌────────────┬────────────┬─────────┐  │
│  │ Listener   │ Listener   │ Certs   │  │
│  │ HTTP:80    │ HTTPS:443  │ SSL     │  │
│  │ (Redirect) │            │         │  │
│  └────────────┴────────────┴─────────┘  │
│                                          │
│  ┌────────────────────────────────────┐ │
│  │  Routing Rules (Host-based)        │ │
│  │  • api.example.com  → API TG       │ │
│  │  • www.example.com  → Web TG       │ │
│  └────────────────────────────────────┘ │
└─────────────────────────────────────────┘
        ↓                     ↓
┌────────────────┐    ┌────────────────┐
│  API Target    │    │  Web Target    │
│  Group         │    │  Group         │
└────────────────┘    └────────────────┘
        ↓                     ↓
┌────────────────┐    ┌────────────────┐
│  ECS Service   │    │  ECS Service   │
│  (API)         │    │  (Web)         │
│  Port: 8080    │    │  Port: 3000    │
└────────────────┘    └────────────────┘
        ↓                     ↓
┌────────────────────────────────────────┐
│          ECS Cluster                   │
│          (Fargate)                     │
└────────────────────────────────────────┘
```

## Troubleshooting

**Problem**: 502 Bad Gateway  
**Solution**: Check health check path returns 200-399

**Problem**: Service not receiving traffic  
**Solution**: Verify host_headers match domain name

**Problem**: SSL certificate error  
**Solution**: Check certificate covers all domains

**Problem**: Terraform validation error  
**Solution**: Ensure unique service names and priorities

## Cost Estimation

For 2 services:

- ALB: ~$16/month (one ALB for all services)
- Target Groups: $0 (included)
- Data Transfer: Variable
- ECS Fargate: Based on CPU/Memory

**Cost Savings**: Using one ALB for multiple services saves ~$16/month per additional service!

## Next Steps

1. ✅ Copy the complete stack code
2. ✅ Update variables with your values
3. ✅ Run `terraform init && terraform plan`
4. ✅ Review and apply
5. ✅ Add more services as needed

## Support & Documentation

- **Full Documentation**: `README.md`
- **Examples**: `EXAMPLES.md`
- **Summary**: `../../../HTTPS_SERVER_ALB_SUMMARY.md`

---

**Ready to deploy? Copy the complete stack above and customize it!** 🚀

