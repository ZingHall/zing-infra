# ECS Cron Job Module

Schedule ECS tasks with cron expressions. This module creates EventBridge rules to run tasks whose definitions are deployed via CI/CD.

## Overview

This module expects task definitions to be created and managed by your CI/CD pipeline. The task family name must follow the pattern: **`cron-${var.name}`**

**Example**: If `name = "daily-backup"`, the task family must be `cron-daily-backup`

## Features

- ✅ **EventBridge Scheduling** - Cron and rate expressions
- ✅ **IAM Roles** - Automatic EventBridge permissions
- ✅ **Security Group** - Auto-created for task networking
- ✅ **Enable/Disable** - Control scheduling easily
- ✅ **Fargate Spot Support** - Save 70% on costs
- ✅ **Task Overrides** - Environment variable customization
- ✅ **CI/CD Ready** - References externally managed task definitions

## Workflow

```
┌─────────────────────────────────────────┐
│  1. CI/CD Pipeline                      │
│     • Builds container image            │
│     • Pushes to ECR                     │
│     • Creates task definition           │
│       Family: cron-daily-backup         │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  2. Terraform (this module)             │
│     • Looks up task: cron-daily-backup  │
│     • Creates EventBridge rule          │
│     • Schedules execution               │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│  3. EventBridge                         │
│     • Triggers on schedule              │
│     • Runs ECS task                     │
└─────────────────────────────────────────┘
```

## Usage

### Basic Example (Daily Backup)

```hcl
module "daily_backup_scheduler" {
  source = "../../../modules/aws/ecs-cron-job"

  name                = "daily-backup"
  description         = "Run backup daily at 2 AM"
  schedule_expression = "cron(0 2 * * ? *)"

  # ECS Configuration
  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids

  tags = {
    Purpose = "backup"
  }
}

# CI/CD must create task definition with family: cron-daily-backup
```

### Cache Warmer (Every 5 Minutes)

```hcl
module "cache_warmer_scheduler" {
  source = "../../../modules/aws/ecs-scheduler"

  name                = "cache-warmer"
  schedule_expression = "rate(5 minutes)"

  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids

  tags = {
    Purpose = "cache-warming"
  }
}

# CI/CD must create task definition with family: cron-cache-warmer
```

### Weekly Cleanup with Fargate Spot

```hcl
module "weekly_cleanup_scheduler" {
  source = "../../../modules/aws/ecs-scheduler"

  name                = "weekly-cleanup"
  description         = "Clean up old data weekly on Sunday"
  schedule_expression = "cron(0 1 ? * SUN *)"

  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids

  # Use Fargate Spot for cost savings (70% cheaper!)
  capacity_provider_strategy = [
    {
      capacity_provider = "FARGATE_SPOT"
      weight            = 100
      base              = 0
    }
  ]

  tags = {
    Purpose = "cleanup"
  }
}

# CI/CD must create task definition with family: cron-weekly-cleanup
```

## Task Definition Naming Convention

**IMPORTANT**: Your CI/CD pipeline must create task definitions following this naming pattern:

```
Task Family Name = cron-${scheduler_name}
```

**Examples**:
- Scheduler name: `daily-backup` → Task family: `cron-daily-backup`
- Scheduler name: `cache-warmer` → Task family: `cron-cache-warmer`
- Scheduler name: `data-sync` → Task family: `cron-data-sync`

## CI/CD Integration Example

### GitHub Actions

```yaml
name: Deploy Scheduled Task

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-east-1
      
      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v1
      
      - name: Build and push image
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          ECR_REPOSITORY: backup-task
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
      
      - name: Register task definition
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          ECR_REPOSITORY: backup-task
          IMAGE_TAG: ${{ github.sha }}
        run: |
          aws ecs register-task-definition \
            --family cron-daily-backup \
            --requires-compatibilities FARGATE \
            --network-mode awsvpc \
            --cpu 512 \
            --memory 1024 \
            --execution-role-arn ${{ secrets.TASK_EXECUTION_ROLE_ARN }} \
            --task-role-arn ${{ secrets.TASK_ROLE_ARN }} \
            --container-definitions '[{
              "name": "app",
              "image": "'$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG'",
              "essential": true,
              "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                  "awslogs-group": "/aws/ecs/cron-daily-backup",
                  "awslogs-region": "us-east-1",
                  "awslogs-stream-prefix": "ecs"
                }
              }
            }]'
```

## Inputs

### Required

| Name | Description | Type |
|------|-------------|------|
| name | Scheduler name (task family will be cron-<name>) | string |
| schedule_expression | Cron or rate expression | string |
| cluster_arn | ECS cluster ARN | string |
| vpc_id | VPC ID | string |
| subnet_ids | Subnet IDs for task | list(string) |

### Optional - Scheduling

| Name | Description | Type | Default |
|------|-------------|------|---------|
| description | Scheduler description | string | "" |
| enabled | Enable/disable scheduler | bool | true |
| task_count | Number of tasks to run | number | 1 |

### Optional - Network

| Name | Description | Type | Default |
|------|-------------|------|---------|
| assign_public_ip | Assign public IP | bool | false |
| launch_type | FARGATE or EC2 | string | "FARGATE" |
| platform_version | Fargate version | string | "LATEST" |
| capacity_provider_strategy | Capacity providers | list(object) | null |

### Optional - Task

| Name | Description | Type | Default |
|------|-------------|------|---------|
| task_input | JSON input override | string | null |

### Optional - Tags

| Name | Description | Type | Default |
|------|-------------|------|---------|
| tags | Resource tags | map(string) | {} |

## Outputs

| Name | Description |
|------|-------------|
| rule_name | EventBridge rule name |
| rule_arn | EventBridge rule ARN |
| task_definition_arn | Task definition ARN (from CI/CD) |
| task_definition_family | Task family name |
| task_family_name | Expected task family (cron-<name>) |
| security_group_id | Task security group ID |
| eventbridge_role_arn | EventBridge role ARN |
| schedule_expression | Schedule expression |
| enabled | Whether enabled |

## Schedule Expression Formats

### Rate Expressions

```hcl
# Every X minutes
schedule_expression = "rate(5 minutes)"

# Every X hours
schedule_expression = "rate(2 hours)"

# Every X days
schedule_expression = "rate(1 day)"
```

### Cron Expressions

Format: `cron(minutes hours day-of-month month day-of-week year)`

```hcl
# Daily at 2 AM UTC
schedule_expression = "cron(0 2 * * ? *)"

# Every weekday at 9 AM
schedule_expression = "cron(0 9 ? * MON-FRI *)"

# Weekly on Sunday at 1 AM
schedule_expression = "cron(0 1 ? * SUN *)"

# Monthly on the 1st at midnight
schedule_expression = "cron(0 0 1 * ? *)"

# Every 15 minutes
schedule_expression = "cron(0/15 * * * ? *)"
```

### Common Schedules

| Schedule | Expression |
|----------|------------|
| Every 5 minutes | `rate(5 minutes)` |
| Every hour | `rate(1 hour)` |
| Daily at 2 AM | `cron(0 2 * * ? *)` |
| Every weekday at 9 AM | `cron(0 9 ? * MON-FRI *)` |
| Weekly on Sunday | `cron(0 0 ? * SUN *)` |
| Monthly on 1st | `cron(0 0 1 * ? *)` |

## Complete Example

```hcl
# ============================================
# CI/CD Pipeline (GitHub Actions, etc.)
# ============================================
# Creates task definition: cron-monthly-report

# ============================================
# Terraform
# ============================================

module "monthly_report_scheduler" {
  source = "../../../modules/aws/ecs-scheduler"

  # Scheduling
  name                = "monthly-report"
  description         = "Generate monthly report on the 1st at 9 AM"
  schedule_expression = "cron(0 9 1 * ? *)"
  enabled             = true

  # ECS Configuration
  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids

  # Task overrides (optional)
  task_input = jsonencode({
    containerOverrides = [
      {
        name = "app"
        environment = [
          {
            name  = "REPORT_TYPE"
            value = "monthly"
          }
        ]
      }
    ]
  })

  # Tags
  tags = {
    Environment = "production"
    Purpose     = "reporting"
  }
}
```

## Enable/Disable Scheduler

```hcl
# Disable temporarily
module "my_scheduler" {
  source = "../../../modules/aws/ecs-scheduler"

  name    = "my-task"
  enabled = false  # Scheduler is disabled

  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids
}
```

## Multiple Schedules for Same Task

```hcl
# Run sync twice a day (same task definition)
module "sync_morning" {
  source = "../../../modules/aws/ecs-scheduler"

  name                = "data-sync-morning"
  schedule_expression = "cron(0 6 * * ? *)"  # 6 AM

  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids
}

module "sync_evening" {
  source = "../../../modules/aws/ecs-scheduler"

  name                = "data-sync-evening"
  schedule_expression = "cron(0 18 * * ? *)"  # 6 PM

  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids
}

# CI/CD creates two task definitions:
# - cron-data-sync-morning
# - cron-data-sync-evening
```

## Best Practices

1. **Naming Convention** - Always use `cron-${name}` for task family
2. **Use Private Subnets** - Run scheduled tasks in private subnets
3. **CI/CD First** - Deploy task definition before running terraform
4. **Enable CloudWatch Logs** - Configure in task definition
5. **Tag Resources** - Use tags for cost tracking
6. **Use Fargate Spot** - Save 70% for non-critical tasks
7. **IAM Roles** - Create execution & task roles in CI/CD

## Cost Optimization

- Use `FARGATE_SPOT` for non-critical tasks (70% savings)
- Right-size CPU/Memory in task definition
- Set log retention in task definition
- Disable unused schedulers with `enabled = false`

## Monitoring

### Check Scheduler Status

```bash
# View rule details
aws events describe-rule --name my-scheduler

# List all schedules
aws events list-rules --name-prefix backup
```

### View Task Execution

```bash
# Check latest task runs
aws ecs list-tasks --cluster my-cluster --family cron-daily-backup

# View task logs (configure in task definition)
aws logs tail /aws/ecs/cron-daily-backup --follow
```

## Troubleshooting

**Problem**: Task definition not found  
**Solution**: Ensure CI/CD has created task with family `cron-${name}`

**Problem**: Scheduler not triggering  
**Solution**: Check `enabled = true` and verify IAM permissions

**Problem**: Task fails to start  
**Solution**: Verify subnet/security group configuration

**Problem**: Wrong execution time  
**Solution**: Remember cron uses UTC timezone

**Problem**: Cannot pull image  
**Solution**: Verify ECR permissions in execution role (set in task definition)

## Required IAM Roles (Created by CI/CD)

Your task definition needs two IAM roles:

### Task Execution Role
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
```

### Task Role
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject"
      ],
      "Resource": "arn:aws:s3:::your-bucket/*"
    }
  ]
}
```

## Related Modules

- **`ecs-cluster`** - Create ECS clusters
- **`ecs-task`** - For one-off manual tasks (also CI/CD managed)
- **`ecs-service`** - For long-running services

---

**Perfect for automated task execution with CI/CD!** ⏰🚀
