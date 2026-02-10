data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.54.1"
    }
  }

  backend "s3" {
    bucket         = "terraform-zing-staging"
    key            = "zing-file-server.tfstate"
    region         = "ap-northeast-1"
    encrypt        = true
    dynamodb_table = "terraform-lock-table"
    profile        = "zing-staging"
  }
}

provider "aws" {
  region  = "ap-northeast-1"
  profile = "zing-staging"

  default_tags {
    tags = {
      environment = "staging"
      module      = "zing-file-server"
      managed_by  = "terraform"
    }
  }
}

# Get network outputs
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket  = "terraform-zing-staging"
    key     = "network.tfstate"
    region  = "ap-northeast-1"
    profile = "zing-staging"
  }
}

locals {
  domain_name = "files.staging.zing.you"
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

  name                 = "zing-file-server"
  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true
  count_number         = 10
  force_delete         = false
}

# ECS Cluster
module "ecs_cluster" {
  source = "../../../modules/aws/ecs-cluster"

  name                               = "zing-file-server"
  container_insights_enabled         = false
  capacity_providers                 = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy = []
}

# ECS Role (with secrets access for SUI_PRIVATE_KEY, HMAC_SECRET, DATABASE_URL)
module "ecs_role" {
  source = "../../../modules/aws/ecs-role"

  name                  = "zing-file-server"
  enable_secrets_access = true
  secrets_arns = [
    "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:zing-file-server-*"
  ]
  ssm_parameter_arns      = []
  log_group_name          = "/ecs/zing-file-server"
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
          Resource = "arn:aws:s3:::zing-staging-static-assets/*"
        }
      ]
    })
  }
}

# HTTPS ALB
module "https_alb" {
  source = "../../../modules/aws/https-alb"

  name            = "zing-file-server"
  vpc_id          = data.terraform_remote_state.network.outputs.vpc_id
  subnet_ids      = data.terraform_remote_state.network.outputs.public_subnet_ids
  certificate_arn = module.acm_cert.cert_arn

  services = [{
    name                             = "zing-file-server"
    port                             = 8080
    host_headers                     = [local.domain_name]
    priority                         = 100
    health_check_path                = "/health_check"
    health_check_matcher             = "200"
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
