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
    key            = "zing-api.tfstate"
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
      module      = "zing-api"
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
