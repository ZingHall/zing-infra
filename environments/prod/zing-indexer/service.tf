# Security Group for ECS Service
# Indexer doesn't need external access, only outbound for blockchain queries
resource "aws_security_group" "ecs_indexer" {
  name        = "zing-indexer-ecs-sg"
  description = "Security group for zing-indexer ECS service"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  # No ingress rules - indexer doesn't accept external connections
  # WebSocket server is for internal use only

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic for blockchain queries"
  }

  tags = {
    application = "zing-indexer"
    purpose     = "blockchain-indexer"
    region      = "ap-northeast-1"
  }
}

# ECS Task Definition (Fargate launch type)
resource "aws_ecs_task_definition" "indexer" {
  family                   = "zing-indexer"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = module.ecs_role.execution_role_arn
  task_role_arn            = module.ecs_role.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "zing-indexer"
      essential = true
      image     = "${module.ecr.repository_url}:${var.image_tag}"

      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "NODE_ENV"
          value = "production"
        },
        {
          name  = "SUI_NETWORK"
          value = "mainnet"
        },
        {
          name  = "WS_PORT"
          value = "8080"
        },
        {
          name  = "WS_HOST"
          value = "0.0.0.0"
        },
        {
          name  = "START_CHECKPOINT"
          value = var.start_checkpoint
        },
        {
          name  = "BATCH_SIZE"
          value = var.batch_size
        },
        {
          name  = "GRPC_MAX_REQUESTS"
          value = var.grpc_max_requests
        },
        {
          name  = "GRPC_WINDOW_SECONDS"
          value = var.grpc_window_seconds
        },
        {
          name  = "LOG_LEVEL"
          value = var.log_level
        },
        {
          name  = "ZING_FRAMEWORK_PACKAGE_MAINNET"
          value = "TODO_FILL_MAINNET_VALUE"
        },
        {
          name  = "ZING_GOVERNANCE_PACKAGE_MAINNET"
          value = "TODO_FILL_MAINNET_VALUE"
        },
        {
          name  = "ZING_GOVERNANCE_TREASURY_MAINNET"
          value = "TODO_FILL_MAINNET_VALUE"
        },
        {
          name  = "ZING_IDENTITY_PACKAGE_MAINNET"
          value = "TODO_FILL_MAINNET_VALUE"
        },
        {
          name  = "ZING_IDENTITY_CONFIG_MAINNET"
          value = "TODO_FILL_MAINNET_VALUE"
        },
        {
          name  = "IDENTITY_PLATFORMS_TWITTER_PACKAGE_MAINNET"
          value = "TODO_FILL_MAINNET_VALUE"
        },
        {
          name  = "IDENTITY_PLATFORMS_TWITTER_RECLAIM_MANAGER_MAINNET"
          value = "TODO_FILL_MAINNET_VALUE"
        },
        {
          name  = "IDENTITY_PLATFORMS_TWITTER_IDENTITY_MANAGER_MAINNET"
          value = "TODO_FILL_MAINNET_VALUE"
        },
        {
          name  = "ZING_STUDIO_PACKAGE_MAINNET"
          value = "TODO_FILL_MAINNET_VALUE"
        },
        {
          name  = "ZING_STUDIO_CONFIG_MAINNET"
          value = "TODO_FILL_MAINNET_VALUE"
        },
        {
          name  = "ZING_STUDIO_STORAGE_TREASURY_MAINNET"
          value = "TODO_FILL_MAINNET_VALUE"
        }
      ]

      # Database URL from secrets (if needed)
      secrets = var.database_url_secret_arn != "" ? [
        {
          name      = "DATABASE_URL"
          valueFrom = var.database_url_secret_arn
        }
      ] : []

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = module.ecs_role.log_group_name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "ecs"
        }
      }

      # Health check (if health endpoint exists)
      healthCheck = var.enable_health_check ? {
        command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      } : null
    }
  ])

  tags = {
    application = "zing-indexer"
    purpose     = "blockchain-indexer"
    region      = "ap-northeast-1"
    environment = "prod"
    network     = "mainnet"
  }
}

# ECS Service (no load balancer - internal service only)
resource "aws_ecs_service" "indexer" {
  name            = "zing-indexer"
  cluster         = module.ecs_cluster.cluster_id
  task_definition = aws_ecs_task_definition.indexer.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [data.terraform_remote_state.network.outputs.private_subnet_ids[1]]
    security_groups  = [aws_security_group.ecs_indexer.id]
    assign_public_ip = false
  }

  deployment_maximum_percent         = var.deployment_maximum_percent
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent

  health_check_grace_period_seconds = var.enable_health_check ? 60 : null

  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  depends_on = [
    aws_ecs_task_definition.indexer
  ]

  lifecycle {
    # Ignore task_definition changes (managed by CI/CD)
    ignore_changes = [
      task_definition
    ]
    # Create new service before destroying old one (for updates)
    create_before_destroy = true
  }

  tags = {
    application = "zing-indexer"
    purpose     = "blockchain-indexer"
    region      = "ap-northeast-1"
    environment = "prod"
    network     = "mainnet"
  }
}
