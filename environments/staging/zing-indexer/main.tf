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
    key            = "zing-indexer.tfstate"
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
      module      = "zing-indexer"
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

# ECR Repository
module "ecr" {
  source = "../../../modules/aws/ecr"

  name                 = "zing-indexer"
  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true
  count_number         = 10
  force_delete         = false
}

# ECS Cluster
module "ecs_cluster" {
  source = "../../../modules/aws/ecs-cluster"

  name                               = "zing-indexer"
  container_insights_enabled         = false
  capacity_providers                 = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy = []
}

# ECS Role
module "ecs_role" {
  source = "../../../modules/aws/ecs-role"

  name                  = "zing-indexer"
  enable_secrets_access = true
  # Grant access to zing-indexer secret (using wildcard to match AWS-generated suffix)
  secrets_arns = [
    "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:zing-indexer-*"
  ]
  ssm_parameter_arns      = []
  log_group_name          = "/ecs/zing-indexer"
  execution_role_policies = {}
  task_role_policies      = {}
}

