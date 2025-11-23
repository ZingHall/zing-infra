# ECR Repository
module "ecr" {
  source = "../../../modules/aws/ecr"

  name                 = "zing-watermark"
  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true
  count_number         = 10
  force_delete         = false
}

# ECS Role
module "ecs_role" {
  source = "../../../modules/aws/ecs-role"

  name                  = "zing-watermark"
  enable_secrets_access = true
  # Use wildcard ARN to match all secret versions (AWS adds random suffix to secret ARNs)
  secrets_arns = [
    var.create_mtls_secret
    ? "${aws_secretsmanager_secret.ecs_server_cert[0].arn}*"
    : "${data.aws_secretsmanager_secret.ecs_server_cert[0].arn}*"
  ]
  ssm_parameter_arns      = []
  log_group_name          = "/ecs/zing-watermark"
  execution_role_policies = {}
  task_role_policies      = {}
}

# Security Group for ECS Service (allow access from NLB and TEE)
# ap-northeast-1 VPC CIDR: 10.0.0.0/16 (where nautilus-enclave is located)
#
# Note: NLB doesn't use security groups (Layer 4), so we allow:
# - VPC CIDR access (covers both NLB traffic and direct TEE access)
# - NLB traffic comes from private subnets (same VPC CIDR)
resource "aws_security_group" "ecs_watermark" {
  name        = "zing-watermark-ecs-sg"
  description = "Security group for zing-watermark ECS service (TEE access only)"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  # Allow traffic from VPC (covers both NLB and direct TEE access)
  # NLB traffic comes from private subnets within the VPC
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] # ap-northeast-1 VPC CIDR (covers NLB and TEE)
    description = "Allow mTLS from NLB and TEE (ap-northeast-1 VPC)"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    application = "zing-watermark"
    purpose     = "watermark-service"
    region      = "ap-northeast-1"
  }

  # Lifecycle: Allow Terraform to manage deletion order
  # Note: Security group will be deleted after ECS service stops all tasks
  lifecycle {
    create_before_destroy = false
  }
}

# ECS Task Definition (Fargate launch type)
resource "aws_ecs_task_definition" "watermark" {
  family                   = "zing-watermark"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = module.ecs_role.execution_role_arn
  task_role_arn            = module.ecs_role.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "watermark"
      essential = true
      image     = "${module.ecr.repository_url}:latest"

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
          name  = "PORT"
          value = "8080"
        },
        {
          name  = "ENCLAVE_ENDPOINT"
          value = "https://enclave.staging.zing.you:3000"
        }
      ]

      secrets = [
        {
          name      = "MTLS_CERT_JSON"
          valueFrom = var.create_mtls_secret ? aws_secretsmanager_secret.ecs_server_cert[0].arn : data.aws_secretsmanager_secret.ecs_server_cert[0].arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = module.ecs_role.log_group_name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "watermark"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = {
    application = "zing-watermark"
    purpose     = "watermark-service"
    region      = "ap-northeast-1"
  }
}

# ECS Service (with NLB for scale out and load balancing)
resource "aws_ecs_service" "watermark" {
  name            = "zing-watermark"
  cluster         = module.ecs_cluster.cluster_id
  task_definition = aws_ecs_task_definition.watermark.arn
  desired_count   = var.desired_count # Scale out: multiple tasks for load balancing
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.terraform_remote_state.network.outputs.private_subnet_ids
    security_groups  = [aws_security_group.ecs_watermark.id]
    assign_public_ip = false
  }

  # Connect to NLB Target Group
  load_balancer {
    target_group_arn = aws_lb_target_group.watermark.arn
    container_name   = "watermark"
    container_port   = 8080
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  health_check_grace_period_seconds = 60

  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  depends_on = [
    aws_ecs_task_definition.watermark,
    aws_lb_listener.watermark # Ensure listener is created before service
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
    application = "zing-watermark"
    purpose     = "watermark-service"
    region      = "ap-northeast-1"
  }
}
