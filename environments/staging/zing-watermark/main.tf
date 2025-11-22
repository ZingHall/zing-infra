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
    key            = "zing-watermark.tfstate"
    region         = "ap-northeast-1" # S3 bucket location (resources deploy to us-east-2)
    encrypt        = true
    dynamodb_table = "terraform-lock-table"
    profile        = "zing-staging"
  }
}

provider "aws" {
  region  = "us-east-2" # AMD SEV-SNP supported region
  profile = "zing-staging"

  default_tags {
    tags = {
      environment = "staging"
      module      = "zing-watermark"
      managed_by  = "terraform"
    }
  }
}

# Get network outputs (us-east-2 VPC)
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket  = "terraform-zing-staging"
    key     = "network.tfstate"
    region  = "ap-northeast-1" # Network state is stored in ap-northeast-1
    profile = "zing-staging"
  }
}

# Get Enclave security group
data "terraform_remote_state" "enclave" {
  backend = "s3"
  config = {
    bucket  = "terraform-zing-staging"
    key     = "nautilus-enclave.tfstate"
    region  = "ap-northeast-1"
    profile = "zing-staging"
  }
}

# ⚠️ WARNING: us-east-2 VPC has been removed from network module
# This service requires a VPC in us-east-2 (AMD SEV-SNP region)
# 
# Options to fix:
# 1. Create a new VPC in us-east-2 (recommended: use a separate network module for us-east-2)
# 2. Migrate this service to a different region (if AMD SEV-SNP is not required)
# 3. Delete this service if no longer needed
#
# To uncomment and use this service, you need to:
# - Create a VPC in us-east-2 with private subnets
# - Update the vpc_id and subnet_ids below
# - Ensure VPC endpoints are configured for ECS, ECR, CloudWatch, etc.

# Confidential Container ECS Cluster
# ⚠️ COMMENTED OUT: Requires VPC in us-east-2 which has been removed
# Uncomment and provide VPC/subnet IDs when ready to deploy
#
# module "confidential_cluster" {
#   source = "../../../modules/confidential-container"
#
#   name       = "zing-watermark"
#   vpc_id     = "vpc-REPLACE_WITH_US_EAST_2_VPC_ID"  # TODO: Create VPC in us-east-2
#   subnet_ids = ["subnet-REPLACE_WITH_US_EAST_2_SUBNET_ID"]  # TODO: Create subnets in us-east-2
#
#   instance_type = "m6a.large"
#   ami_os        = "amazon-linux-2023"
#
#   min_size         = 1
#   max_size         = 3
#   desired_capacity = 1
#
#   # Enable mTLS for TEE Gateway architecture
#   # ECS acts as SERVER, TEE acts as CLIENT
#   enable_enclave_mtls = true
#
#   # Enclave security group (TEE will connect as client)
#   # Note: Enclave is in ap-northeast-1, ECS is in us-east-2
#   # Security groups can't reference across regions, so we use CIDR blocks instead
#   # The module will use CIDR blocks for cross-region communication
#   enclave_security_group_ids = [] # Empty - using CIDR blocks in security group rules instead
#
#   # ECS service endpoint (where TEE should connect)
#   enclave_endpoints = [
#     "zing-watermark.internal:8080"
#   ]
#
#   # mTLS server certificates (ECS uses these to accept TEE connections)
#   # These should be created separately and stored in Secrets Manager
#   mtls_certificate_secrets_arns = var.mtls_certificate_secrets_arns
#
#   mtls_certificate_path = "/etc/ecs/mtls"
#
#   container_insights_enabled = true
#   enable_managed_scaling     = true
#   target_capacity            = 80
#
#   root_volume_size = 50
#   root_volume_type = "gp3"
#
#   # CloudWatch Logs for instance logs
#   log_group_name = "/ecs/zing-watermark-instances"
#
#   tags = {
#     application = "zing-watermark"
#     purpose     = "confidential-computing"
#   }
# }

