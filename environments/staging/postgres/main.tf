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
    key            = "postgres.tfstate"
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
      module      = "postgres"
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

data "terraform_remote_state" "zing-web" {
  backend = "s3"
  config = {
    bucket  = "terraform-zing-staging"
    key     = "zing-web.tfstate"
    region  = "ap-northeast-1"
    profile = "zing-staging"
  }
}

data "terraform_remote_state" "bastion-host" {
  backend = "s3"
  config = {
    bucket  = "terraform-zing-staging"
    key     = "bastion-host.tfstate"
    region  = "ap-northeast-1"
    profile = "zing-staging"
  }
}

data "terraform_remote_state" "zing-indexer" {
  backend = "s3"
  config = {
    bucket  = "terraform-zing-staging"
    key     = "zing-indexer.tfstate"
    region  = "ap-northeast-1"
    profile = "zing-staging"
  }
}

data "terraform_remote_state" "zing-api" {
  backend = "s3"
  config = {
    bucket  = "terraform-zing-staging"
    key     = "zing-api.tfstate"
    region  = "ap-northeast-1"
    profile = "zing-staging"
  }
}

# PostgreSQL Database
module "postgres" {
  source = "../../../modules/aws/postgres"

  name                  = "staging-postgres"
  engine_version        = "17.6"        # PostgreSQL 17.6 (matches postgres17 parameter group family)
  instance_class        = "db.t3.micro" # Cost-effective: smallest instance class
  allocated_storage     = 20            # Minimal storage for staging
  max_allocated_storage = 100           # Auto-scaling up to 100GB if needed

  # Storage settings - cost-effective
  iops              = null # Use gp2 (cheaper than io1)
  storage_encrypted = true
  kms_key_id        = null

  # Database settings
  db_name     = var.db_name
  db_username = var.db_username
  db_password = var.db_password

  # Network settings
  vpc_id     = data.terraform_remote_state.network.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids

  # High availability - disabled for cost savings
  multi_az           = false # Single AZ saves ~50% cost
  availability_zone  = data.terraform_remote_state.network.outputs.availability_zones[1]
  ca_cert_identifier = null

  # Backup settings - reduced for staging
  backup_retention_period = 3 # 3 days instead of 7 (cost savings)
  backup_target           = "region"
  blue_green_update       = false
  apply_immediately       = false

  # Security settings - relaxed for staging
  deletion_protection         = false # Allow deletion for staging
  skip_final_snapshot         = true  # Skip final snapshot (cost savings)
  final_snapshot_identifier   = null
  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false

  # Monitoring - minimal for cost savings
  monitoring_interval             = 0 # Disabled (saves cost)
  monitoring_role_arn             = null
  performance_insights_enabled    = false # Disabled (saves cost)
  enabled_cloudwatch_logs_exports = []    # No CloudWatch logs (saves cost)

  # Database parameters
  max_connections            = 87 # Formula: LEAST({DBInstanceClassMemory/9531392}, 5000) for db.t3.micro
  log_min_duration_statement = "1000"
  log_lock_waits             = "off"
  log_error_verbosity        = "default"
  log_min_error_statement    = "ERROR"

  # Access control - allow ECS services and bastion host
  accessible_sg_ids = [
    data.terraform_remote_state.bastion-host.outputs.bastion_security_group_id,
    data.terraform_remote_state.zing-indexer.outputs.security_group_id,
    data.terraform_remote_state.zing-api.outputs.ecs_service_sg_id
  ]
}

