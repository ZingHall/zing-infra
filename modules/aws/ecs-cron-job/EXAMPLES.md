# ECS Cron Job - Usage Examples

## Example 1: Daily Backup at 2 AM

```hcl
module "daily_backup" {
  source = "../../../modules/aws/ecs-cron-job"

  name                = "daily-backup"
  description         = "Run database backup daily at 2 AM UTC"
  schedule_expression = "cron(0 2 * * ? *)"

  # ECS Configuration
  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids

  # Task Configuration
  container_image   = "backup-tool:latest"
  container_command = ["./backup.sh", "--full"]

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

  tags = {
    Environment = "production"
    Purpose     = "backup"
  }
}
```

## Example 2: Cache Warmer Every 5 Minutes

```hcl
module "cache_warmer" {
  source = "../../../modules/aws/ecs-cron-job"

  name                = "cache-warmer"
  description         = "Warm cache every 5 minutes"
  schedule_expression = "rate(5 minutes)"

  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids

  container_image   = "cache-warmer:latest"
  container_command = ["./warm-cache.sh"]

  task_cpu    = 256
  task_memory = 512

  environment_variables = {
    REDIS_HOST = var.redis_endpoint
    API_URL    = "https://api.example.com"
    TIMEOUT    = "60"
  }

  tags = {
    Purpose = "cache-warming"
  }
}
```

## Example 3: Weekly Cleanup (Sunday 1 AM)

```hcl
module "weekly_cleanup" {
  source = "../../../modules/aws/ecs-cron-job"

  name                = "weekly-cleanup"
  description         = "Run cleanup weekly on Sunday at 1 AM"
  schedule_expression = "cron(0 1 ? * SUN *)"

  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids

  container_image   = "${var.ecr_url}/cleanup:latest"
  container_command = ["python", "cleanup.py", "--older-than", "90"]

  task_cpu    = 512
  task_memory = 1024

  environment_variables = {
    ENVIRONMENT = "production"
    DRY_RUN     = "false"
  }

  secrets = {
    DATABASE_URL = var.database_secret_arn
  }

  # Use Fargate Spot for cost savings (70% cheaper!)
  capacity_provider_strategy = [
    {
      capacity_provider = "FARGATE_SPOT"
      weight            = 100
      base              = 0
    }
  ]

  log_retention_days = 90

  tags = {
    Purpose = "cleanup"
  }
}
```

## Example 4: Monthly Report (1st of Month at 9 AM)

```hcl
module "monthly_report" {
  source = "../../../modules/aws/ecs-cron-job"

  name                = "monthly-report-generation"
  description         = "Generate monthly report on the 1st at 9 AM"
  schedule_expression = "cron(0 9 1 * ? *)"

  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids

  container_image   = "report-generator:latest"
  container_command = ["node", "generate-report.js"]

  task_cpu    = 1024
  task_memory = 2048

  environment_variables = {
    REPORT_BUCKET = "my-reports-bucket"
    REGION        = "us-east-1"
    REPORT_TYPE   = "monthly"
    FORMAT        = "pdf"
  }

  secrets = {
    DATABASE_URL     = var.database_secret_arn
    SENDGRID_API_KEY = var.sendgrid_api_key_arn
  }

  tags = {
    Purpose = "reporting"
  }
}

# Add custom S3 permissions
resource "aws_iam_role_policy" "report_s3" {
  name = "report-s3-access"
  role = module.monthly_report.task_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "arn:aws:s3:::my-reports-bucket/*"
      }
    ]
  })
}
```

## Example 5: Weekday Morning Task (Mon-Fri at 8 AM)

```hcl
module "morning_summary" {
  source = "../../../modules/aws/ecs-cron-job"

  name                = "morning-summary-weekdays"
  description         = "Send morning summary on weekdays at 8 AM"
  schedule_expression = "cron(0 8 ? * MON-FRI *)"

  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids

  container_image   = "summary-generator:latest"
  container_command = ["./generate-summary.sh"]

  task_cpu    = 512
  task_memory = 1024

  environment_variables = {
    SLACK_CHANNEL = "#daily-summary"
  }

  secrets = {
    SLACK_TOKEN = var.slack_token_arn
  }

  tags = {
    Purpose = "notifications"
  }
}
```

## Example 6: Multiple Schedules for Same Task

```hcl
# Morning sync (6 AM)
module "sync_morning" {
  source = "../../../modules/aws/ecs-cron-job"

  name                = "data-sync-morning"
  description         = "Morning data sync at 6 AM"
  schedule_expression = "cron(0 6 * * ? *)"

  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids

  container_image   = "data-sync:latest"
  container_command = ["./sync.sh"]

  task_cpu    = 512
  task_memory = 1024

  environment_variables = {
    SOURCE_API = "https://api.example.com"
    TARGET_DB  = var.database_endpoint
  }

  secrets = {
    API_KEY = var.api_key_secret_arn
  }
}

# Evening sync (6 PM)
module "sync_evening" {
  source = "../../../modules/aws/ecs-cron-job"

  name                = "data-sync-evening"
  description         = "Evening data sync at 6 PM"
  schedule_expression = "cron(0 18 * * ? *)"

  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids

  container_image   = "data-sync:latest"
  container_command = ["./sync.sh"]

  task_cpu    = 512
  task_memory = 1024

  environment_variables = {
    SOURCE_API = "https://api.example.com"
    TARGET_DB  = var.database_endpoint
  }

  secrets = {
    API_KEY = var.api_key_secret_arn
  }
}
```

## Example 7: Disabled Scheduler (for Testing)

```hcl
module "test_scheduler" {
  source = "../../../modules/aws/ecs-cron-job"

  name                = "test-scheduler"
  description         = "Test scheduler (disabled)"
  schedule_expression = "cron(0 0 * * ? *)"
  enabled             = false  # Disabled for now

  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids

  container_image   = "test:latest"
  container_command = ["./test.sh"]

  task_cpu    = 256
  task_memory = 512

  tags = {
    Environment = "testing"
  }
}
```

## Example 8: Complete Production Setup with Multiple Schedulers

```hcl
# ============================================
# ECS Cluster
# ============================================

module "cluster" {
  source = "../../../modules/aws/ecs-cluster"

  name                       = "scheduled-tasks-cluster"
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
}

# ============================================
# Scheduled Tasks
# ============================================

# Daily backup at 2 AM
module "backup_scheduler" {
  source = "../../../modules/aws/ecs-cron-job"

  name                = "daily-backup"
  schedule_expression = "cron(0 2 * * ? *)"

  cluster_arn = module.cluster.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids

  container_image   = "backup:latest"
  container_command = ["./backup.sh"]

  task_cpu    = 1024
  task_memory = 2048

  secrets = {
    DB_PASSWORD = var.db_password_secret_arn
  }
}

# Weekly cleanup on Sunday
module "cleanup_scheduler" {
  source = "../../../modules/aws/ecs-cron-job"

  name                = "weekly-cleanup"
  schedule_expression = "cron(0 1 ? * SUN *)"

  cluster_arn = module.cluster.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids

  container_image   = "cleanup:latest"
  container_command = ["./cleanup.sh"]

  task_cpu    = 512
  task_memory = 1024
}

# Monthly report on 1st
module "report_scheduler" {
  source = "../../../modules/aws/ecs-cron-job"

  name                = "monthly-report"
  schedule_expression = "cron(0 9 1 * ? *)"

  cluster_arn = module.cluster.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids

  container_image   = "report:latest"
  container_command = ["./report.sh"]

  task_cpu    = 512
  task_memory = 1024
}

# Cache warmer every 10 minutes
module "cache_warmer" {
  source = "../../../modules/aws/ecs-cron-job"

  name                = "cache-warmer"
  schedule_expression = "rate(10 minutes)"

  cluster_arn = module.cluster.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids

  container_image   = "cache-warmer:latest"
  container_command = ["./warm-cache.sh"]

  task_cpu    = 256
  task_memory = 512

  environment_variables = {
    REDIS_HOST = var.redis_endpoint
  }
}
```

## Example 9: With Custom IAM Policies

```hcl
module "data_export" {
  source = "../../../modules/aws/ecs-cron-job"

  name                = "data-export"
  schedule_expression = "cron(0 3 * * ? *)"

  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids

  container_image   = "data-exporter:latest"
  container_command = ["python", "export.py", "--format", "csv"]

  task_cpu    = 2048
  task_memory = 4096

  environment_variables = {
    OUTPUT_BUCKET = "my-exports-bucket"
    REGION        = "us-east-1"
    BATCH_SIZE    = "1000"
  }

  secrets = {
    DATABASE_URL = var.database_secret_arn
  }
}

# Add S3 permissions to task role
resource "aws_iam_role_policy" "export_s3" {
  name = "export-s3-access"
  role = module.data_export.task_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject"
        ]
        Resource = "arn:aws:s3:::my-exports-bucket/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = "arn:aws:s3:::my-exports-bucket"
      }
    ]
  })
}
```

## Example 10: Dynamic Enable/Disable

```hcl
# Use variable to control scheduler
variable "enable_backup" {
  description = "Enable backup scheduler"
  type        = bool
  default     = true
}

module "backup_scheduler" {
  source = "../../../modules/aws/ecs-cron-job"

  name                = "backup"
  schedule_expression = "cron(0 2 * * ? *)"
  enabled             = var.enable_backup  # Dynamic control

  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids

  container_image = "backup:latest"
}
```

## Common Schedule Patterns

```hcl
# Every 5 minutes
schedule_expression = "rate(5 minutes)"

# Every hour
schedule_expression = "rate(1 hour)"

# Every day at 2 AM
schedule_expression = "cron(0 2 * * ? *)"

# Every weekday at 9 AM
schedule_expression = "cron(0 9 ? * MON-FRI *)"

# Every Sunday at 1 AM
schedule_expression = "cron(0 1 ? * SUN *)"

# First day of month at midnight
schedule_expression = "cron(0 0 1 * ? *)"

# Every 15 minutes
schedule_expression = "cron(0/15 * * * ? *)"

# Twice daily (6 AM and 6 PM)
schedule_expression_morning = "cron(0 6 * * ? *)"
schedule_expression_evening = "cron(0 18 * * ? *)"
```

## Cost Optimization with Fargate Spot

```hcl
module "scheduler_with_spot" {
  source = "../../../modules/aws/ecs-cron-job"

  name                = "cleanup"
  schedule_expression = "cron(0 1 ? * SUN *)"

  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids

  container_image = "cleanup:latest"

  # Use 100% Fargate Spot (70% cost savings!)
  capacity_provider_strategy = [
    {
      capacity_provider = "FARGATE_SPOT"
      weight            = 100
      base              = 0
    }
  ]
}
```

## Best Practices

1. **Use Private Subnets** - Run tasks in private subnets for security
2. **Right-size Resources** - Match CPU/Memory to actual needs
3. **Use Secrets Manager** - Store sensitive data securely
4. **Set Log Retention** - Balance cost vs debugging needs
5. **Use Fargate Spot** - Save 70% on non-critical tasks
6. **Tag Everything** - Use tags for cost tracking
7. **Monitor Execution** - Check CloudWatch logs regularly

---

**Perfect for automating ECS task execution!** ⏰🚀
