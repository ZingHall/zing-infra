data "aws_region" "current" {}


locals {
  base_container = {
    name      = var.container_name
    essential = true
    image     = "${var.name}:latest"
    portMappings = [
      {
        containerPort = var.container_port
        hostPort      = var.container_port
        protocol      = "tcp"
      }
    ]
  }
  container_with_logs = merge(local.base_container, var.log_group_name != "" ? {
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = var.log_group_name
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = var.container_name
      }
    }
  } : {})
}


resource "aws_security_group" "ecs" {
  name        = "${var.name}-sg"
  description = "ECS Service security group"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
    description     = "Allow ALB access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn
  container_definitions    = jsonencode([local.container_with_logs])
}

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.container_name
    container_port   = var.container_port
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = var.assign_public_ip
  }

  # 部署配置（顶级属性，不是 block）
  deployment_maximum_percent         = var.deployment_maximum_percent
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent

  # Service Connect 配置
  dynamic "service_connect_configuration" {
    for_each = var.enable_service_connect ? [1] : []

    content {
      enabled   = true
      namespace = var.service_connect_namespace
    }
  }

  # 健康檢查寬限期
  health_check_grace_period_seconds = var.health_check_grace_period_seconds > 0 ? var.health_check_grace_period_seconds : null

  # ECS 管理的標籤
  enable_ecs_managed_tags = var.enable_ecs_managed_tags
  propagate_tags          = var.propagate_tags != "NONE" ? var.propagate_tags : null

  depends_on = [aws_ecs_task_definition.this]
  tags       = var.tags

  lifecycle {
    ignore_changes = [
      task_definition
    ]
  }
}
