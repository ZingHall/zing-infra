# Complete ECS Ecosystem Guide

A comprehensive guide to building production-ready ECS infrastructure with 5 powerful modules.

## 📦 Module Overview

```
┌─────────────────────────────────────────────────────────┐
│                    1. ecs-cluster                       │
│           Shared cluster for all workloads              │
└─────────────────────────────────────────────────────────┘
                          ↓
        ┌─────────────────┴─────────────────┐
        ↓                                   ↓
┌───────────────────┐              ┌───────────────────┐
│   2. https-alb    │              │   4. ecs-task     │
│  Load balancing   │              │ Task definitions  │
│   + Routing       │              │  (batch jobs)     │
└─────────┬─────────┘              └─────────┬─────────┘
          ↓                                  ↓
┌───────────────────┐              ┌───────────────────┐
│  3. ecs-service   │              │ 5. ecs-scheduler  │
│ Long-running apps │              │  Cron scheduling  │
└───────────────────┘              └───────────────────┘
```

## 🎯 Use Case Matrix

| Module | Purpose | When to Use |
|--------|---------|-------------|
| **ecs-cluster** | Create ECS cluster | Always - foundation for all workloads |
| **https-alb** | Load balancing | For public-facing web apps & APIs |
| **ecs-service** | Long-running services | For web servers, APIs, workers |
| **ecs-task** | Task definitions | For one-off or scheduled tasks |
| **ecs-scheduler** | Schedule tasks | For cron jobs, periodic tasks |

## 🚀 Quick Start Examples

### Example 1: Simple Web App

```hcl
# 1. Cluster
module "cluster" {
  source = "../../../modules/aws/ecs-cluster"
  name   = "web-cluster"
}

# 2. ALB
module "alb" {
  source = "../../../modules/aws/https-alb"

  name            = "web"
  vpc_id          = var.vpc_id
  subnet_ids      = var.public_subnet_ids
  certificate_arn = var.cert_arn

  services = [
    {
      name         = "app"
      port         = 3000
      host_headers = ["www.example.com"]
      priority     = 100
    }
  ]
}

# 3. Service
module "web_service" {
  source = "../../../modules/aws/ecs-service"

  name                  = "app"
  cluster_id            = module.cluster.cluster_id
  alb_security_group_id = module.alb.alb_security_group_id
  target_group_arn      = module.alb.target_group_arns["app"]

  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids
  container_port     = 3000
}
```

### Example 2: API with Daily Backup

```hcl
# 1. Cluster
module "cluster" {
  source = "../../../modules/aws/ecs-cluster"
  name   = "api-cluster"
}

# 2. ALB
module "alb" {
  source = "../../../modules/aws/https-alb"

  name            = "api"
  vpc_id          = var.vpc_id
  subnet_ids      = var.public_subnet_ids
  certificate_arn = var.cert_arn

  services = [
    {
      name         = "api"
      port         = 8080
      host_headers = ["api.example.com"]
      priority     = 100
    }
  ]
}

# 3. API Service
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
}

# 4. Backup Task
module "backup_task" {
  source = "../../../modules/aws/ecs-task"

  name            = "backup"
  vpc_id          = var.vpc_id
  container_image = "backup:latest"

  task_cpu    = 512
  task_memory = 1024
}

# 5. Schedule Backup
module "backup_scheduler" {
  source = "../../../modules/aws/ecs-scheduler"

  name                = "daily-backup"
  schedule_expression = "cron(0 2 * * ? *)"

  cluster_arn            = module.cluster.cluster_arn
  task_definition_arn    = module.backup_task.task_definition_arn
  task_execution_role_arn = module.backup_task.execution_role_arn
  task_role_arn          = module.backup_task.task_role_arn

  subnet_ids         = var.private_subnet_ids
  security_group_ids = [module.backup_task.security_group_id]
}
```

### Example 3: Complete Production Setup

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

  services = [
    {
      name                 = "api"
      port                 = 8080
      host_headers         = ["api.example.com"]
      priority             = 100
      health_check_path    = "/health"
      deregistration_delay = 15
    },
    {
      name                 = "web"
      port                 = 3000
      host_headers         = ["www.example.com"]
      priority             = 101
      stickiness_enabled   = true
    },
    {
      name              = "admin"
      port              = 3000
      host_headers      = ["admin.example.com"]
      priority          = 102
    }
  ]
}

# ============================================
# 3. ECS SERVICES (Long-Running)
# ============================================

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
}

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
}

# ============================================
# 4. ECS TASKS (Batch/Scheduled)
# ============================================

module "migration_task" {
  source = "../../../modules/aws/ecs-task"

  name              = "migration"
  vpc_id            = var.vpc_id
  container_image   = "${var.ecr_url}/api:latest"
  container_command = ["npm", "run", "migrate"]

  task_cpu    = 512
  task_memory = 1024

  secrets = {
    DATABASE_URL = var.database_secret_arn
  }
}

module "backup_task" {
  source = "../../../modules/aws/ecs-task"

  name              = "backup"
  vpc_id            = var.vpc_id
  container_image   = "backup:latest"
  container_command = ["./backup.sh"]

  task_cpu    = 1024
  task_memory = 2048

  secrets = {
    DB_PASSWORD = var.db_password_secret_arn
  }
}

module "cleanup_task" {
  source = "../../../modules/aws/ecs-task"

  name              = "cleanup"
  vpc_id            = var.vpc_id
  container_image   = "cleanup:latest"
  container_command = ["./cleanup.sh"]

  task_cpu    = 512
  task_memory = 1024
}

# ============================================
# 5. SCHEDULERS
# ============================================

# Daily backup at 2 AM
module "backup_scheduler" {
  source = "../../../modules/aws/ecs-scheduler"

  name                = "daily-backup"
  schedule_expression = "cron(0 2 * * ? *)"

  cluster_arn            = module.cluster.cluster_arn
  task_definition_arn    = module.backup_task.task_definition_arn
  task_execution_role_arn = module.backup_task.execution_role_arn
  task_role_arn          = module.backup_task.task_role_arn

  subnet_ids         = var.private_subnet_ids
  security_group_ids = [module.backup_task.security_group_id]
}

# Weekly cleanup on Sunday
module "cleanup_scheduler" {
  source = "../../../modules/aws/ecs-scheduler"

  name                = "weekly-cleanup"
  schedule_expression = "cron(0 1 ? * SUN *)"

  cluster_arn            = module.cluster.cluster_arn
  task_definition_arn    = module.cleanup_task.task_definition_arn
  task_execution_role_arn = module.cleanup_task.execution_role_arn
  task_role_arn          = module.cleanup_task.task_role_arn

  subnet_ids         = var.private_subnet_ids
  security_group_ids = [module.cleanup_task.security_group_id]
}
```

## 📊 Module Comparison

| Module | Lines | Resources | Complexity |
|--------|-------|-----------|------------|
| ecs-cluster | 30 | 1 | Simple |
| https-alb | 172 | 8+ | Medium |
| ecs-service | 276 | 7 | Medium |
| ecs-task | 190 | 5 | Simple |
| ecs-scheduler | 257 | 3 | Simple |

## 🎓 Learning Path

1. **Start with `ecs-cluster`** - Foundation for everything
2. **Add `ecs-service`** - Deploy your first app (no ALB yet)
3. **Add `https-alb`** - Add load balancing for public access
4. **Add `ecs-task`** - Create batch/migration tasks
5. **Add `ecs-scheduler`** - Automate task execution

## 💰 Cost Breakdown (Typical Setup)

```
1 ECS Cluster:              $0
1 HTTPS ALB:                ~$16/month
3 ECS Services:             ~$150/month (depends on size)
4 Scheduled Tasks:          ~$5/month
Total:                      ~$171/month + data transfer
```

**Savings**: One ALB for multiple services saves ~$32/month! 💰

## 🔍 Module Selection Guide

### When to use `ecs-cluster`
- ✅ Always - it's the foundation
- Creates: ECS cluster
- Use cases: Shared cluster for all workloads

### When to use `https-alb`
- ✅ Public-facing web apps
- ✅ REST APIs
- ✅ Multiple services sharing one ALB
- Creates: ALB, listeners, target groups, routing rules
- Use cases: HTTPS load balancing

### When to use `ecs-service`
- ✅ Long-running applications
- ✅ Web servers
- ✅ REST APIs
- ✅ Background workers
- Creates: ECS service, task definition, security group, IAM roles
- Use cases: Always-running services

### When to use `ecs-task`
- ✅ One-off tasks
- ✅ Database migrations
- ✅ Batch processing
- ✅ Data imports/exports
- Creates: Task definition, security group, IAM roles
- Use cases: Tasks that run and complete

### When to use `ecs-scheduler`
- ✅ Cron jobs
- ✅ Scheduled backups
- ✅ Periodic maintenance
- ✅ Report generation
- Creates: EventBridge rule, IAM role
- Use cases: Automated task execution

## 🎯 Common Patterns

### Pattern 1: Web App
- Modules: `ecs-cluster` + `https-alb` + `ecs-service`
- Best for: Web applications, APIs

### Pattern 2: API + Scheduled Tasks
- Modules: `ecs-cluster` + `https-alb` + `ecs-service` + `ecs-task` + `ecs-scheduler`
- Best for: APIs with background jobs

### Pattern 3: Microservices
- Modules: `ecs-cluster` + `https-alb` + `ecs-service` (×N)
- Best for: Multiple services sharing one ALB

### Pattern 4: Batch Processing
- Modules: `ecs-cluster` + `ecs-task` + `ecs-scheduler`
- Best for: Scheduled data processing

## 📚 Documentation

### Module READMEs
- `modules/aws/ecs-cluster/README.md`
- `modules/aws/https-alb/README.md`
- `modules/aws/ecs-service/README.md`
- `modules/aws/ecs-task/README.md`
- `modules/aws/ecs-scheduler/README.md`

### Examples
- `modules/aws/https-alb/EXAMPLES.md`
- `modules/aws/ecs-task/EXAMPLES.md`
- `modules/aws/ecs-scheduler/EXAMPLES.md`

### Guides
- `modules/aws/COMPLETE_ECS_STACK.md`
- `modules/aws/ECS_COMPLETE_EXAMPLE.md`
- `modules/aws/ECS_ECOSYSTEM_GUIDE.md` (this file)

## 🚀 Getting Started

1. **Copy the complete example** from `ECS_COMPLETE_EXAMPLE.md`
2. **Customize** with your values
3. **Deploy** with `terraform apply`
4. **Scale** by adding more services/tasks

## ✅ Best Practices

1. **Use Private Subnets** - Run ECS tasks in private subnets
2. **Share ALB** - One ALB for multiple services
3. **Use Fargate Spot** - Save 70% on non-critical tasks
4. **Enable Container Insights** - Monitor performance
5. **Tag Everything** - Track costs and resources
6. **Set Log Retention** - Balance cost vs debugging
7. **Use Secrets Manager** - Store sensitive data securely

## 🔧 Troubleshooting

### Service not starting
- Check task definition
- Verify IAM permissions
- Check CloudWatch logs

### ALB returning 502
- Check health check path
- Verify container port
- Check security groups

### Scheduled task not running
- Verify scheduler is enabled
- Check cron expression (UTC)
- Verify IAM permissions

### Cost too high
- Use Fargate Spot
- Right-size CPU/Memory
- Check log retention
- Monitor data transfer

## 🎉 Success!

You now have a complete ECS ecosystem that can handle:
- ✅ Web applications
- ✅ APIs
- ✅ Microservices
- ✅ Background jobs
- ✅ Scheduled tasks
- ✅ Batch processing
- ✅ And more!

**Start building amazing cloud infrastructure!** 🚀

