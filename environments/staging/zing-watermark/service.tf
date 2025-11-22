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
  secrets_arns          = var.secrets_arns
  ssm_parameter_arns    = var.ssm_parameter_arns
  log_group_name        = "/ecs/zing-watermark"
  execution_role_policies = {
    ECRPull = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }]
    })
  }
  task_role_policies = {}
}

# Security Group for ECS Service (additional rules for TEE connectivity)
# Use CIDR block since enclave is in different region (ap-northeast-1)
# ap-northeast-1 VPC CIDR: 10.0.0.0/16
resource "aws_security_group_rule" "ecs_from_tee" {
  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/16"] # ap-northeast-1 VPC CIDR (where enclave is located)
  security_group_id = module.confidential_cluster.security_group_id
  description       = "Allow mTLS from TEE Gateway (ap-northeast-1 VPC via peering)"
}

# ECS Task Definition (EC2 launch type)
resource "aws_ecs_task_definition" "watermark" {
  family                   = "zing-watermark"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge" # EC2 uses bridge mode
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = module.ecs_role.execution_role_arn
  task_role_arn            = module.ecs_role.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "watermark"
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
          name  = "PORT"
          value = "8080"
        },
        {
          name  = "ENCLAVE_ENDPOINT"
          value = "https://enclave.staging.zing.you:3000"
        }
      ]

      secrets = concat(
        var.secrets_arns != null ? [
          for secret_arn in var.secrets_arns : {
            name      = replace(split(":", secret_arn)[6], "/", "_")
            valueFrom = secret_arn
          }
        ] : [],
        var.ssm_parameter_arns != null ? [
          for param_arn in var.ssm_parameter_arns : {
            name      = replace(split(":", param_arn)[6], "/", "_")
            valueFrom = param_arn
          }
        ] : []
      )

      # Note: For EC2 bridge mode, volumes are not supported in task definition
      # Certificates are available at /etc/ecs/mtls on the host
      # Container should bind mount this path or access via host network

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

  # Note: For EC2 launch type with bridge network mode, volumes are not supported
  # Certificates are mounted directly from host path /etc/ecs/mtls
  # Container should access certificates at /etc/ecs/mtls (mounted via bind mount in container)

  tags = {
    Environment = "staging"
    Application = "zing-watermark"
  }
}

# ECS Service (EC2 launch type via capacity provider)
resource "aws_ecs_service" "watermark" {
  name            = "zing-watermark"
  cluster         = module.confidential_cluster.cluster_id
  task_definition = aws_ecs_task_definition.watermark.arn
  desired_count   = var.desired_count

  # Use capacity provider strategy (removed launch_type - cannot use both)
  capacity_provider_strategy {
    capacity_provider = module.confidential_cluster.capacity_provider_name
    weight            = 1
    base              = 1
  }

  # Note: EC2 launch type with bridge network mode doesn't support network_configuration
  # Security groups are configured at the instance level (in launch template)

  # Place tasks in us-east-2 subnets
  placement_constraints {
    type       = "memberOf"
    expression = "attribute:ecs.availability-zone in [us-east-2a, us-east-2b]"
  }

  # Deployment configuration (top-level attributes, not block)
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  health_check_grace_period_seconds = 60

  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  depends_on = [
    aws_ecs_task_definition.watermark,
    module.confidential_cluster
  ]

  tags = {
    Environment = "staging"
    Application = "zing-watermark"
  }

  lifecycle {
    ignore_changes = [
      task_definition
    ]
  }
}

