locals {
  domain_name = "api.prod.zing.you"
}

# ACM Certificate
module "acm_cert" {
  source = "../../../modules/aws/acm-cert"

  description      = "ACM certificate for ${local.domain_name}"
  domain_name      = local.domain_name
  hosted_zone_name = data.terraform_remote_state.network.outputs.hosted_zone_name
}

# ECR Repository
module "ecr" {
  source = "../../../modules/aws/ecr"

  name                 = "zing-api"
  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true
  count_number         = 10
  force_delete         = false
}

# ECS Cluster
module "ecs_cluster" {
  source = "../../../modules/aws/ecs-cluster"

  name                               = "zing-api"
  container_insights_enabled         = false
  capacity_providers                 = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy = []
}

# ECS Role
module "ecs_role" {
  source = "../../../modules/aws/ecs-role"

  name                  = "zing-api"
  enable_secrets_access = true
  secrets_arns = [
    "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:zing-api-*"
  ]
  ssm_parameter_arns      = []
  log_group_name          = "/ecs/zing-api"
  execution_role_policies = {}
  task_role_policies = {
    s3-access = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:PutObject",
            "s3:GetObject",
            "s3:DeleteObject"
          ]
          Resource = "arn:aws:s3:::zing-prod-static-assets/*"
        }
      ]
    })
  }
}

# HTTPS ALB
module "https_alb" {
  source = "../../../modules/aws/https-alb"

  name            = "zing-api"
  vpc_id          = data.terraform_remote_state.network.outputs.vpc_id
  subnet_ids      = data.terraform_remote_state.network.outputs.public_subnet_ids
  certificate_arn = module.acm_cert.cert_arn

  services = [{
    name                             = "zing-api"
    port                             = 3000
    host_headers                     = [local.domain_name]
    priority                         = 100
    health_check_path                = "/health"
    health_check_matcher             = "200-399"
    health_check_interval            = 30
    health_check_timeout             = 5
    health_check_healthy_threshold   = 2
    health_check_unhealthy_threshold = 2
    deregistration_delay             = 30
    stickiness_enabled               = false
    stickiness_duration              = 86400
  }]

  internal                    = false
  ingress_cidr_blocks         = ["0.0.0.0/0"]
  http_redirect               = true
  ssl_policy                  = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  additional_certificate_arns = []
  access_log_bucket           = ""
  access_log_prefix           = ""
}

# ECS Service
module "ecs_service" {
  source = "../../../modules/aws/ecs-service"

  name                  = "zing-api"
  cluster_id            = module.ecs_cluster.cluster_id
  alb_security_group_id = module.https_alb.alb_security_group_id
  target_group_arn      = module.https_alb.target_group_arns["zing-api"]
  execution_role_arn    = module.ecs_role.execution_role_arn
  task_role_arn         = module.ecs_role.task_role_arn
  desired_count         = 1
  vpc_id                = data.terraform_remote_state.network.outputs.vpc_id
  private_subnet_ids    = [data.terraform_remote_state.network.outputs.private_subnet_ids[1]]
  assign_public_ip      = false
  container_name        = "app"
  container_port        = 3000
  task_cpu              = 256
  task_memory           = 512
  log_group_name        = module.ecs_role.log_group_name
}

# Route53 Record
resource "aws_route53_record" "api" {
  zone_id = data.terraform_remote_state.network.outputs.hosted_zone_id
  name    = local.domain_name
  type    = "A"

  alias {
    name                   = module.https_alb.alb_dns_name
    zone_id                = module.https_alb.alb_zone_id
    evaluate_target_health = true
  }
}
