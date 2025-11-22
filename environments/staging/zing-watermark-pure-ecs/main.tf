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
    key            = "zing-watermark-pure-ecs.tfstate"
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
      module      = "zing-watermark-pure-ecs"
      managed_by  = "terraform"
    }
  }
}

# Get network outputs (ap-northeast-1 VPC)
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket  = "terraform-zing-staging"
    key     = "network.tfstate"
    region  = "ap-northeast-1"
    profile = "zing-staging"
  }
}

# Pure ECS Cluster (Fargate-based, no EC2 instances)
module "ecs_cluster" {
  source = "../../../modules/aws/ecs-cluster"

  name = "zing-watermark-pure-ecs"

  container_insights_enabled = true

  # Use Fargate capacity providers
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  # Default capacity provider strategy: prefer FARGATE_SPOT for cost savings
  # with FARGATE as fallback
  default_capacity_provider_strategy = [
    {
      capacity_provider = "FARGATE_SPOT"
      weight            = 4
      base              = 0
    },
    {
      capacity_provider = "FARGATE"
      weight            = 1
      base              = 1
    }
  ]

  tags = {
    application = "zing-watermark"
    purpose     = "pure-ecs-cluster"
    region      = "ap-northeast-1"
  }
}

