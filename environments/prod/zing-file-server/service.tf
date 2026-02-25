# Security group for ECS tasks - allows ALB ingress on container port
resource "aws_security_group" "ecs_file_server" {
  name        = "zing-file-server-ecs-sg"
  description = "Security group for zing-file-server ECS service"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [module.https_alb.alb_security_group_id]
    description     = "Allow ALB access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    application = "zing-file-server"
    purpose     = "file-encryption-server"
    region      = "ap-northeast-1"
  }
}

# ECS Task Definition (bootstrap template - managed by CI/CD in zing-file-server repo)
resource "aws_ecs_task_definition" "file_server" {
  family                   = "zing-file-server"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = module.ecs_role.execution_role_arn
  task_role_arn            = module.ecs_role.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "app"
      essential = true
      image     = "${module.ecr.repository_url}:latest"
      portMappings = [{ containerPort = 8080, hostPort = 8080, protocol = "tcp" }]
    }
  ])
}

# ECS Service
resource "aws_ecs_service" "file_server" {
  name            = "zing-file-server"
  cluster         = module.ecs_cluster.cluster_id
  task_definition = aws_ecs_task_definition.file_server.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  load_balancer {
    target_group_arn = module.https_alb.target_group_arns["zing-file-server"]
    container_name   = "app"
    container_port   = 8080
  }

  network_configuration {
    subnets          = [data.terraform_remote_state.network.outputs.private_subnet_ids[1]]
    security_groups  = [aws_security_group.ecs_file_server.id]
    assign_public_ip = false
  }

  deployment_maximum_percent         = var.deployment_maximum_percent
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent

  health_check_grace_period_seconds = 60

  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  depends_on = [
    aws_ecs_task_definition.file_server
  ]

  lifecycle {
    ignore_changes = [
      task_definition
    ]
    create_before_destroy = true
  }

  tags = {
    application = "zing-file-server"
    purpose     = "file-encryption-server"
    region      = "ap-northeast-1"
    environment = "prod"
    network     = "mainnet"
  }
}

# Route53 Record
resource "aws_route53_record" "file_server" {
  zone_id = data.terraform_remote_state.network.outputs.hosted_zone_id
  name    = local.domain_name
  type    = "A"

  alias {
    name                   = module.https_alb.alb_dns_name
    zone_id                = module.https_alb.alb_zone_id
    evaluate_target_health = true
  }
}
