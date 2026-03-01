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
    bucket         = "terraform-zing-prod"
    key            = "zing-async.tfstate"
    region         = "ap-northeast-1"
    encrypt        = true
    dynamodb_table = "terraform-lock-table"
    profile        = "zing-prod"
  }
}

provider "aws" {
  region  = "ap-northeast-1"
  profile = "zing-prod"

  default_tags {
    tags = {
      environment = "prod"
      module      = "zing-async"
      managed_by  = "terraform"
    }
  }
}

# Get network outputs
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket  = "terraform-zing-prod"
    key     = "network.tfstate"
    region  = "ap-northeast-1"
    profile = "zing-prod"
  }
}

# ECR Repository
module "ecr" {
  source = "../../../modules/aws/ecr"

  name                 = "zing-storage-pruner"
  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true
  count_number         = 10
  force_delete         = false
}

# ECS Cluster
module "ecs_cluster" {
  source = "../../../modules/aws/ecs-cluster"

  name                               = "zing-async"
  container_insights_enabled         = false
  capacity_providers                 = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy = []
}

# ECS Role
module "ecs_role" {
  source = "../../../modules/aws/ecs-role"

  name                  = "zing-storage-pruner"
  enable_secrets_access = true
  secrets_arns = [
    "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:zing-storage-pruner-*"
  ]
  ssm_parameter_arns      = []
  log_group_name          = "/ecs/zing-storage-pruner"
  execution_role_policies = {}
  task_role_policies = {
    s3-access = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:DeleteObject",
            "s3:ListBucket"
          ]
          Resource = [
            "arn:aws:s3:::zing-prod-static-assets",
            "arn:aws:s3:::zing-prod-static-assets/*"
          ]
        }
      ]
    })
  }
}

# Cron Job - runs daily at 2 AM UTC
module "cron_job" {
  source = "../../../modules/aws/ecs-cron-job"

  name                = "zing-storage-pruner"
  description         = "Prunes unused storage resources on a daily schedule"
  schedule_expression = "cron(0 2 * * ? *)"
  enabled             = true

  cluster_arn = module.ecs_cluster.cluster_arn
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id
  subnet_ids  = data.terraform_remote_state.network.outputs.private_subnet_ids

  capacity_provider_strategy = [
    {
      capacity_provider = "FARGATE_SPOT"
      weight            = 100
      base              = 0
    }
  ]
}
