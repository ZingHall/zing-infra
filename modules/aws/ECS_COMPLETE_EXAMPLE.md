# Complete ECS Stack - Full Example

This example shows how to use all 4 ECS modules together to build a complete production system.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Route 53 DNS                            │
│         api.example.com → ALB → API Service                     │
│         www.example.com → ALB → Web Service                     │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                      Application Load Balancer                  │
│           (HTTPS:443 with SSL, HTTP→HTTPS redirect)             │
└─────────────────────────────────────────────────────────────────┘
                              ↓
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
   ┌────▼────┐           ┌────▼────┐          ┌────▼────┐
   │ API TG  │           │ Web TG  │          │   ...   │
   └────┬────┘           └────┬────┘          └────┬────┘
        │                     │                     │
   ┌────▼────┐           ┌────▼────┐          ┌────▼────┐
   │   API   │           │   Web   │          │  Admin  │
   │ Service │           │ Service │          │ Service │
   │ (ECS)   │           │ (ECS)   │          │  (ECS)  │
   └────┬────┘           └────┬────┘          └────┬────┘
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                        ECS Cluster                              │
│                      (Fargate / Spot)                           │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                      ECS Tasks (Scheduled)                      │
│    • Daily Backup (2 AM)                                        │
│    • Cache Warmer (Every 5 min)                                 │
│    • Weekly Cleanup (Sunday 1 AM)                               │
│    • DB Migration (On-demand)                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Complete Terraform Configuration

```hcl
# ============================================
# 1. ECS CLUSTER
# ============================================

module "cluster" {
  source = "../../../modules/aws/ecs-cluster"

  name                       = "prod-cluster"
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

# ============================================
# 2. HTTPS ALB (Multiple Services)
# ============================================

module "alb" {
  source = "../../../modules/aws/https-alb"

  name            = "prod"
  vpc_id          = var.vpc_id
  subnet_ids      = var.public_subnet_ids
  certificate_arn = var.wildcard_cert_arn

  # Access logging
  access_log_bucket = aws_s3_bucket.alb_logs.bucket
  access_log_prefix = "prod-alb/"

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
      stickiness_duration  = 3600
    },
    {
      name              = "admin"
      port              = 3000
      host_headers      = ["admin.example.com"]
      priority          = 102
      health_check_path = "/admin/health"
    }
  ]

  tags = local.tags
}

# ============================================
# 3. ECS SERVICES (Long-Running)
# ============================================

# API Service
module "api_service" {
  source = "../../../modules/aws/ecs-service"

  name                  = "api"
  cluster_id            = module.cluster.cluster_id
  alb_security_group_id = module.alb.alb_security_group_id
  target_group_arn      = module.alb.target_group_arns["api"]

  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids

  container_port = 8080
  desired_count  = 5
  task_cpu       = 512
  task_memory    = 1024

  tags = local.tags
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

  container_port = 3000
  desired_count  = 3
  task_cpu       = 256
  task_memory    = 512

  tags = local.tags
}

# Admin Service
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

  tags = local.tags
}

# ============================================
# 4. ECS TASKS (Scheduled & On-Demand)
# ============================================

# Database Migration (On-Demand)
module "migration_task" {
  source = "../../../modules/aws/ecs-task"

  name              = "db-migration"
  vpc_id            = var.vpc_id
  container_image   = "${var.ecr_url}/api:latest"
  container_command = ["npm", "run", "migrate:up"]

  task_cpu    = 512
  task_memory = 1024

  environment_variables = {
    NODE_ENV = "production"
  }

  secrets = {
    DATABASE_URL = var.database_secret_arn
  }

  tags = merge(local.tags, {
    Purpose = "migration"
  })
}

# Daily Backup (Scheduled at 2 AM)
module "backup_task" {
  source = "../../../modules/aws/ecs-task"

  name              = "daily-backup"
  vpc_id            = var.vpc_id
  container_image   = "backup-tool:latest"
  container_command = ["./backup.sh", "--incremental"]

  task_cpu    = 1024
  task_memory = 2048

  environment_variables = {
    BACKUP_BUCKET = "my-backups-bucket"
    RETENTION     = "30"
  }

  secrets = {
    DB_PASSWORD = var.db_password_secret_arn
  }

  log_retention_days = 30

  tags = merge(local.tags, {
    Purpose = "backup"
  })
}

resource "aws_cloudwatch_event_rule" "daily_backup" {
  name                = "daily-backup-schedule"
  description         = "Run backup daily at 2 AM"
  schedule_expression = "cron(0 2 * * ? *)"
}

resource "aws_cloudwatch_event_target" "daily_backup" {
  rule      = aws_cloudwatch_event_rule.daily_backup.name
  target_id = "backup-task"
  arn       = module.cluster.cluster_arn
  role_arn  = aws_iam_role.eventbridge_ecs.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = module.backup_task.task_definition_arn
    launch_type         = "FARGATE"

    network_configuration {
      subnets          = var.private_subnet_ids
      security_groups  = [module.backup_task.security_group_id]
      assign_public_ip = false
    }
  }
}

# Cache Warmer (Every 5 Minutes)
module "cache_warmer" {
  source = "../../../modules/aws/ecs-task"

  name              = "cache-warmer"
  vpc_id            = var.vpc_id
  container_image   = "cache-warmer:latest"
  container_command = ["./warm-cache.sh"]

  task_cpu    = 256
  task_memory = 512

  environment_variables = {
    REDIS_HOST = var.redis_endpoint
    API_URL    = "https://api.example.com"
  }

  tags = merge(local.tags, {
    Purpose = "cache-warming"
  })
}

resource "aws_cloudwatch_event_rule" "cache_warming" {
  name                = "cache-warming-schedule"
  description         = "Warm cache every 5 minutes"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "cache_warming" {
  rule      = aws_cloudwatch_event_rule.cache_warming.name
  target_id = "cache-warmer"
  arn       = module.cluster.cluster_arn
  role_arn  = aws_iam_role.eventbridge_ecs.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = module.cache_warmer.task_definition_arn
    launch_type         = "FARGATE"

    network_configuration {
      subnets          = var.private_subnet_ids
      security_groups  = [module.cache_warmer.security_group_id]
      assign_public_ip = false
    }
  }
}

# Weekly Cleanup (Sunday 1 AM)
module "cleanup_task" {
  source = "../../../modules/aws/ecs-task"

  name              = "weekly-cleanup"
  vpc_id            = var.vpc_id
  container_image   = "${var.ecr_url}/cleanup:latest"
  container_command = ["python", "cleanup.py", "--older-than", "90"]

  task_cpu    = 512
  task_memory = 1024

  environment_variables = {
    ENVIRONMENT = "production"
  }

  secrets = {
    DATABASE_URL = var.database_secret_arn
  }

  log_retention_days = 90

  tags = merge(local.tags, {
    Purpose = "cleanup"
  })
}

resource "aws_cloudwatch_event_rule" "weekly_cleanup" {
  name                = "weekly-cleanup-schedule"
  description         = "Run cleanup weekly on Sunday at 1 AM"
  schedule_expression = "cron(0 1 ? * SUN *)"
}

resource "aws_cloudwatch_event_target" "weekly_cleanup" {
  rule      = aws_cloudwatch_event_rule.weekly_cleanup.name
  target_id = "cleanup-task"
  arn       = module.cluster.cluster_arn
  role_arn  = aws_iam_role.eventbridge_ecs.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = module.cleanup_task.task_definition_arn
    launch_type         = "FARGATE"

    network_configuration {
      subnets          = var.private_subnet_ids
      security_groups  = [module.cleanup_task.security_group_id]
      assign_public_ip = false
    }
  }
}

# ============================================
# IAM ROLE FOR EVENTBRIDGE
# ============================================

resource "aws_iam_role" "eventbridge_ecs" {
  name = "eventbridge-ecs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "eventbridge_ecs" {
  name = "eventbridge-ecs-policy"
  role = aws_iam_role.eventbridge_ecs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecs:RunTask"
        Resource = "*"
        Condition = {
          StringLike = {
            "ecs:cluster" = module.cluster.cluster_arn
          }
        }
      },
      {
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = [
          module.backup_task.execution_role_arn,
          module.backup_task.task_role_arn,
          module.cache_warmer.execution_role_arn,
          module.cache_warmer.task_role_arn,
          module.cleanup_task.execution_role_arn,
          module.cleanup_task.task_role_arn
        ]
      }
    ]
  })
}

# ============================================
# DNS RECORDS
# ============================================

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

# ============================================
# S3 BUCKET FOR ALB LOGS
# ============================================

resource "aws_s3_bucket" "alb_logs" {
  bucket = "my-alb-logs-${data.aws_caller_identity.current.account_id}"

  tags = local.tags
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

# ============================================
# OUTPUTS
# ============================================

output "cluster_name" {
  description = "ECS cluster name"
  value       = module.cluster.cluster_name
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.alb.alb_dns_name
}

output "service_endpoints" {
  description = "Service HTTPS endpoints"
  value       = module.alb.service_endpoints
}

output "api_service_name" {
  description = "API service name"
  value       = module.api_service.ecs_service_name
}

output "web_service_name" {
  description = "Web service name"
  value       = module.web_service.ecs_service_name
}

output "migration_task_arn" {
  description = "Migration task definition ARN"
  value       = module.migration_task.task_definition_arn
}

# ============================================
# DATA SOURCES
# ============================================

data "aws_caller_identity" "current" {}
data "aws_elb_service_account" "main" {}

# ============================================
# LOCAL VARIABLES
# ============================================

locals {
  tags = {
    Environment = "production"
    Team        = "platform"
    ManagedBy   = "terraform"
    Project     = "my-app"
  }
}
```

## Summary

This complete example demonstrates:

1. **1 ECS Cluster** - Shared cluster using Fargate and Spot
2. **1 HTTPS ALB** - Load balancer for 3 services
3. **3 ECS Services** - API, Web, Admin (long-running)
4. **4 ECS Tasks** - Migration, Backup, Cache Warmer, Cleanup (scheduled/on-demand)

Total: **8 workloads on 1 cluster** with proper routing, security, and automation! 🚀

## Cost Estimate

- **ECS Cluster**: $0 (pay per task)
- **ALB**: ~$16/month
- **3 ECS Services**: ~$150/month (varies by size)
- **4 Scheduled Tasks**: ~$5/month
- **Total**: ~$171/month + data transfer

**Savings**: One ALB for all services saves ~$32/month! 💰

