# Data source to get the task definition created by CI/CD
data "aws_ecs_task_definition" "this" {
  task_definition = "cron-${var.name}"
}

# Security Group for Task
resource "aws_security_group" "task" {
  name        = "${var.name}-cron-sg"
  description = "Security group for scheduled ECS task ${var.name}"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(var.tags, {
    Name = "${var.name}-cron-sg"
  })
}

# EventBridge Rule for Scheduling
resource "aws_cloudwatch_event_rule" "this" {
  name                = var.name
  description         = var.description
  schedule_expression = var.schedule_expression
  state               = var.enabled ? "ENABLED" : "DISABLED"

  tags = var.tags
}

# EventBridge Target (ECS Task)
resource "aws_cloudwatch_event_target" "ecs_task" {
  rule      = aws_cloudwatch_event_rule.this.name
  target_id = "${var.name}-task"
  arn       = var.cluster_arn
  role_arn  = aws_iam_role.eventbridge.arn

  ecs_target {
    task_count          = var.task_count
    task_definition_arn = data.aws_ecs_task_definition.this.arn
    launch_type         = var.launch_type
    platform_version    = var.platform_version

    network_configuration {
      subnets          = var.subnet_ids
      security_groups  = [aws_security_group.task.id]
      assign_public_ip = var.assign_public_ip
    }

    dynamic "capacity_provider_strategy" {
      for_each = var.capacity_provider_strategy != null ? var.capacity_provider_strategy : []
      content {
        capacity_provider = capacity_provider_strategy.value.capacity_provider
        weight            = capacity_provider_strategy.value.weight
        base              = lookup(capacity_provider_strategy.value, "base", null)
      }
    }
  }

  input = var.task_input
}

# Data sources
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
