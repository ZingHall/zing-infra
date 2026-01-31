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
          value = "staging"
        },
        {
          name  = "SUI_NETWORK"
          value = "testnet"
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
          name  = "ZING_FRAMEWORK_PACKAGE_TESTNET"
          value = "0xd851eb5b907b60aa5fd958dd74044d809c49ee60001cad621726f03ea138f943"
        },
        {
          name  = "ZING_GOVERNANCE_PACKAGE_TESTNET"
          value = "0xbac95464c775b45ff0fb066be432fa1eb269e03162a274165c3f89324306c44e"
        },
        {
          name  = "ZING_GOVERNANCE_TREASURY_TESTNET"
          value = "0xca56bc3982525decbd4b025d3d4ae4de07259d6efc187577bfc3ab212e20574f"
        },
        {
          name  = "ZING_IDENTITY_PACKAGE_TESTNET"
          value = "0xaaf27a90890ac1efface4fbb22597e95829cbe6cbb771df02f0d2cc93f067c70"
        },
        {
          name  = "ZING_IDENTITY_CONFIG_TESTNET"
          value = "0xde2eb80aa01db47e65b705c80af931ccb1d56a8a6a06403e205fa8fb1ad4a02e"
        },
        {
          name  = "IDENTITY_PLATFORMS_TWITTER_PACKAGE_TESTNET"
          value = "0xa0d84dc088ba37e3108e69458c4dc0d0f836479f384fbe1fe98c737d27945c3e"
        },
        {
          name  = "IDENTITY_PLATFORMS_TWITTER_RECLAIM_MANAGER_TESTNET"
          value = "0x3d3c56359728f12f8b54e9e2f5d5861a168f7d75675b83afc7f8b9cce289bfc1"
        },
        {
          name  = "IDENTITY_PLATFORMS_TWITTER_IDENTITY_MANAGER_TESTNET"
          value = "0x44e9171b465f9bbad19864c06cec7ad24d3e830198fe10d9acc84f4e31ad59f6"
        },
        {
          name  = "ZING_STUDIO_PACKAGE_TESTNET"
          value = "0xfdaff57965f92c6c477fdc4054065afd51bed4d45591ac683981993497f29f95"
        },
        {
          name  = "ZING_STUDIO_CONFIG_TESTNET"
          value = "0xcd6aaf5eabc5541c7615feee2e50197dc46e660527844eba0ed655884ff30abb"
        },
        {
          name  = "ZING_STUDIO_STORAGE_TREASURY_TESTNET"
          value = "0x21b5c05884f9a3e6f594877e0a979fc6183387f2c6613d03fac2c252239b910b"
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
    environment = "staging"
    network     = "testnet"
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
    environment = "staging"
    network     = "testnet"
  }
}

