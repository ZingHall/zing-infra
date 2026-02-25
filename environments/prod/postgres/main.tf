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
    key            = "postgres.tfstate"
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
      module      = "postgres"
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

data "terraform_remote_state" "bastion-host" {
  backend = "s3"
  config = {
    bucket  = "terraform-zing-prod"
    key     = "bastion-host.tfstate"
    region  = "ap-northeast-1"
    profile = "zing-prod"
  }
}

data "terraform_remote_state" "zing-indexer" {
  backend = "s3"
  config = {
    bucket  = "terraform-zing-prod"
    key     = "zing-indexer.tfstate"
    region  = "ap-northeast-1"
    profile = "zing-prod"
  }
}

data "terraform_remote_state" "zing-api" {
  backend = "s3"
  config = {
    bucket  = "terraform-zing-prod"
    key     = "zing-api.tfstate"
    region  = "ap-northeast-1"
    profile = "zing-prod"
  }
}

data "terraform_remote_state" "zing-file-server" {
  backend = "s3"
  config = {
    bucket  = "terraform-zing-prod"
    key     = "zing-file-server.tfstate"
    region  = "ap-northeast-1"
    profile = "zing-prod"
  }
}

# PostgreSQL Database
module "postgres" {
  source = "../../../modules/aws/postgres"

  name                  = "prod-postgres"
  engine_version        = "17.6"
  instance_class        = "db.t3.micro"
  allocated_storage     = 20
  max_allocated_storage = 100

  # Storage settings
  iops              = null
  storage_encrypted = true
  kms_key_id        = null

  # Database settings
  db_name     = var.db_name
  db_username = var.db_username
  db_password = var.db_password

  # Network settings
  vpc_id     = data.terraform_remote_state.network.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids

  # High availability
  multi_az           = false
  availability_zone  = data.terraform_remote_state.network.outputs.availability_zones[1]
  ca_cert_identifier = null

  # Backup settings
  backup_retention_period = 3
  backup_target           = "region"
  blue_green_update       = false
  apply_immediately       = false

  # Security settings
  deletion_protection         = false
  skip_final_snapshot         = true
  final_snapshot_identifier   = null
  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false

  # Monitoring
  monitoring_interval             = 0
  monitoring_role_arn             = null
  performance_insights_enabled    = false
  enabled_cloudwatch_logs_exports = []

  # Database parameters
  max_connections            = 87
  log_min_duration_statement = "1000"
  log_lock_waits             = "off"
  log_error_verbosity        = "default"
  log_min_error_statement    = "ERROR"

  # Access control - allow ECS services and bastion host
  accessible_sg_ids = [
    data.terraform_remote_state.bastion-host.outputs.bastion_security_group_id,
    data.terraform_remote_state.zing-indexer.outputs.security_group_id,
    data.terraform_remote_state.zing-api.outputs.ecs_service_sg_id,
    data.terraform_remote_state.zing-file-server.outputs.security_group_id
  ]
}
