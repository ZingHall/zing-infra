# Complete ECS Stack - Quick Reference

## 🎯 The Complete ECS Stack

Build production-ready ECS infrastructure with 4 modules:

```
┌──────────────────────────────────────┐
│  1. ecs-cluster                      │
│     Creates ECS cluster              │
└──────────────────────────────────────┘
              ↓
┌──────────────────────────────────────┐
│  2. https-alb                        │
│     Creates ALB + Target Groups      │
│     + Routing for all services       │
└──────────────────────────────────────┘
              ↓
┌──────────────────────────────────────┐
│  3. ecs-service (per service)        │
│     Deploys long-running services    │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│  4. ecs-task (per task)              │
│     Batch jobs & scheduled tasks     │
└──────────────────────────────────────┘
```

## 📋 Complete Example (Copy & Paste)

```hcl
# ============================================
# Complete Production ECS Setup
# ============================================

# 1. Create ECS Cluster
module "cluster" {
  source = "../../../modules/aws/ecs-cluster"

  name                       = "prod-cluster"
  container_insights_enabled = true

  tags = {
    Environment = "production"
  }
}

# 2. Create ALB with all services
module "alb" {
  source = "../../../modules/aws/https-alb"

  name            = "prod"
  vpc_id          = var.vpc_id
  subnet_ids      = var.public_subnet_ids
  certificate_arn = var.wildcard_cert_arn

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
      host_headers = ["www.example.com", "example.com"]
      priority     = 101
      stickiness_enabled = true
    },
    {
      name         = "admin"
      port         = 3000
      host_headers = ["admin.example.com"]
      priority     = 102
    }
  ]

  tags = {
    Environment = "production"
  }
}

# 3. Create ECS Services
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

  tags = {
    Environment = "production"
    Service     = "api"
  }
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

  tags = {
    Environment = "production"
    Service     = "web"
  }
}

module "admin_service" {
  source = "../../../modules/aws/ecs-service"

  name                  = "admin"
  cluster_id            = module.cluster.cluster_id
  alb_security_group_id = module.alb.alb_security_group_id
  target_group_arn      = module.alb.target_group_arns["admin"]

  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids

  container_port = 3000
  desired_count  = 1
  task_cpu       = 256
  task_memory    = 512

  tags = {
    Environment = "production"
    Service     = "admin"
  }
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

# 5. Outputs
output "cluster_name" {
  value = module.cluster.cluster_name
}

output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "service_endpoints" {
  value = module.alb.service_endpoints
}
```

## 📊 Module Comparison

| Module | Purpose | Creates | Lines |
|--------|---------|---------|-------|
| `ecs-cluster` | Cluster management | ECS Cluster | ~30 |
| `https-server-alb` | Load balancing | ALB, TGs, Rules | ~50 |
| `ecs-service` × 3 | Service deployment | Task Def, Service, SG | ~60 |
| **Total** | **Complete stack** | **All resources** | **~140** |

## 🎨 Architecture Diagram

```
                 ┌─────────────────┐
                 │   Route 53 DNS  │
                 │  api.example.com│
                 │  www.example.com│
                 │admin.example.com│
                 └────────┬────────┘
                          │
                 ┌────────▼────────┐
                 │      ALB        │
                 │   (HTTPS:443)   │
                 │  HTTP→HTTPS     │
                 └────────┬────────┘
                          │
         ┌────────────────┼────────────────┐
         │                │                │
    ┌────▼────┐      ┌────▼────┐     ┌────▼────┐
    │  API TG │      │  Web TG │     │Admin TG │
    └────┬────┘      └────┬────┘     └────┬────┘
         │                │                │
    ┌────▼────┐      ┌────▼────┐     ┌────▼────┐
    │   API   │      │   Web   │     │  Admin  │
    │ Service │      │ Service │     │ Service │
    │ :8080   │      │ :3000   │     │ :3000   │
    └─────────┘      └─────────┘     └─────────┘
         │                │                │
         └────────────────┼────────────────┘
                          │
                 ┌────────▼────────┐
                 │   ECS Cluster   │
                 │    (Fargate)    │
                 └─────────────────┘
```

## 🚀 Quick Commands

```bash
# Initialize
terraform init

# Plan
terraform plan

# Apply
terraform apply

# Get ALB DNS
terraform output alb_dns_name

# Get service endpoints
terraform output service_endpoints
```

## 📝 Adding a New Service (3 Steps)

### Step 1: Add to ALB services list
```hcl
services = [
  { name = "api",   priority = 100 },
  { name = "web",   priority = 101 },
  { name = "admin", priority = 102 },
  { name = "mobile", port = 8082, host_headers = ["mobile.example.com"], priority = 103 },  # NEW!
]
```

### Step 2: Create ECS service
```hcl
module "mobile_service" {
  source = "../../../modules/aws/ecs-service"

  name                  = "mobile"
  cluster_id            = module.cluster.cluster_id
  alb_security_group_id = module.alb.alb_security_group_id
  target_group_arn      = module.alb.target_group_arns["mobile"]

  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids
  container_port     = 8082
  desired_count      = 2

  tags = var.tags
}
```

### Step 3: Add DNS record
```hcl
resource "aws_route53_record" "mobile" {
  zone_id = var.hosted_zone_id
  name    = "mobile.example.com"
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}
```

**Done! Just 3 simple steps to add a new service!** ✅

## 💡 Module Features Summary

### 1. ecs-cluster
```hcl
✓ Creates ECS cluster
✓ Container insights support
✓ Capacity providers (Fargate/Spot)
✓ Simple, focused
```

### 2. https-alb (NEW!)
```hcl
✓ ALB + Target Groups + Routing
✓ Multi-service support
✓ HTTPS-first
✓ Automatic validation
✓ Session stickiness
✓ Custom health checks
```

### 3. ecs-service
```hcl
✓ Task definition
✓ ECS service
✓ Security group
✓ IAM roles
✓ CloudWatch logs
✓ Auto-scaling ready
```

### 4. ecs-task (NEW!)
```hcl
✓ Task definition (one-off)
✓ IAM roles
✓ CloudWatch logs
✓ Security group
✓ Environment variables
✓ Secrets support
✓ Scheduled execution
```

## 📖 Module Documentation

| Module | README | Examples |
|--------|--------|----------|
| `ecs-cluster` | [README](ecs-cluster/README.md) | - |
| `https-alb` | [README](https-alb/README.md) | [EXAMPLES](https-alb/EXAMPLES.md) |
| `ecs-service` | [README](ecs-service/README.md) | - |
| `ecs-task` | [README](ecs-task/README.md) | [EXAMPLES](ecs-task/EXAMPLES.md) |

## 🎯 Best Practices

1. **Use Wildcard Certificates**
   ```hcl
   certificate_arn = var.wildcard_cert_arn  # *.example.com
   ```

2. **Leave Priority Gaps**
   ```hcl
   priorities: 100, 110, 120  # Easy to insert new services
   ```

3. **Enable Container Insights**
   ```hcl
   container_insights_enabled = true
   ```

4. **Use Health Endpoints**
   ```hcl
   health_check_path = "/health"  # Dedicated endpoint
   ```

5. **Enable Stickiness Only When Needed**
   ```hcl
   stickiness_enabled = true  # For stateful apps only
   ```

## 🔍 Troubleshooting

**Problem**: Service shows as unhealthy  
**Solution**: Check health_check_path returns 200-399

**Problem**: 502 Bad Gateway  
**Solution**: Ensure container port matches in ALB and ECS service

**Problem**: Domain not routing  
**Solution**: Verify host_headers match DNS records

**Problem**: SSL certificate error  
**Solution**: Ensure certificate covers all domains

## 💰 Cost Estimation (3 Services)

- **ECS Cluster**: $0 (pay per task)
- **ALB**: ~$16/month (one ALB for all services) ✅
- **ECS Fargate**: Based on CPU/Memory
  - API (512/1024): ~$26/month/task
  - Web (256/512): ~$13/month/task
  - Admin (256/512): ~$13/month/task
- **Data Transfer**: Variable

**Total**: ~$88/month base + data transfer

**Savings**: Sharing one ALB saves $16/month per additional service! 💰

## ✅ Status

- ✅ All modules created
- ✅ Fully validated
- ✅ Production ready
- ✅ Comprehensive documentation
- ✅ Real-world examples

## 🚀 Get Started

1. Copy the complete example above
2. Update variables with your values
3. Run `terraform plan`
4. Review and apply
5. Deploy your services!

---

**Built with ❤️ for ECS on AWS**

