data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.54.1"
    }
  }

  backend "s3" {
    bucket         = "terraform-zing-staging"
    key            = "bastion-host.tfstate"
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
      module      = "bastion-host"
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

# Create a map of private subnet IDs to route table IDs
locals {
  private_subnet_route_table_map = zipmap(
    data.terraform_remote_state.network.outputs.private_subnet_ids,
    data.terraform_remote_state.network.outputs.private_route_table_ids
  )
}

# Bastion Host
module "bastion_host" {
  source = "../../../modules/aws/bastion-host"

  name      = "staging-bastion"
  vpc_id    = data.terraform_remote_state.network.outputs.vpc_id
  subnet_id = data.terraform_remote_state.network.outputs.public_subnet_ids[0]

  private_subnet_route_table_map = local.private_subnet_route_table_map

  allowed_cidr_blocks = ["0.0.0.0/0"]
  ssh_public_key      = var.ssh_public_key

  instance_type = "t4g.nano"
  allocate_eip  = true

  create_dns_record = true
  route53_zone_id   = data.terraform_remote_state.network.outputs.hosted_zone_id
  dns_name          = "bastion.staging.zing.you"
  dns_ttl           = "300"
}

