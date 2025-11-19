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
    key            = "nautilus-enclave.tfstate"
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
      module      = "nautilus-enclave"
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

# S3 Bucket for EIF artifacts
resource "aws_s3_bucket" "enclave_artifacts" {
  bucket = "zing-enclave-artifacts-staging"

  tags = {
    Name        = "zing-enclave-artifacts-staging"
    Environment = "staging"
    Purpose     = "nitro-enclave-eif-storage"
  }
}

resource "aws_s3_bucket_versioning" "enclave_artifacts" {
  bucket = aws_s3_bucket.enclave_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "enclave_artifacts" {
  bucket = aws_s3_bucket.enclave_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "enclave_artifacts" {
  bucket = aws_s3_bucket.enclave_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "enclave_artifacts" {
  bucket = aws_s3_bucket.enclave_artifacts.id

  rule {
    id     = "delete-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "delete-old-eif-files"
    status = "Enabled"

    expiration {
      days = 90
    }
  }
}

# Nitro Enclave Deployment
module "nautilus_enclave" {
  source = "../../../modules/aws/enclave"

  name       = "nautilus-watermark-staging"
  vpc_id     = data.terraform_remote_state.network.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids

  s3_bucket_name = aws_s3_bucket.enclave_artifacts.bucket
  s3_bucket_arn  = aws_s3_bucket.enclave_artifacts.arn
  eif_version    = var.eif_version
  eif_path       = "eif/staging"

  instance_type    = "m5.xlarge"
  min_size         = 1
  max_size         = 2
  desired_capacity = 1

  enclave_cpu_count = 2
  enclave_memory_mb = 512
  enclave_port      = 3000
  enclave_init_port = 3001

  allowed_cidr_blocks = [
    data.terraform_remote_state.network.outputs.vpc_cidr_block
  ]

  secrets_arns = []

  enable_auto_scaling       = true
  target_cpu_utilization    = 70
  target_memory_utilization = 80

  health_check_grace_period = 300

  root_volume_size = 200
  root_volume_type = "gp3"

  enable_public_ip = false

  create_dns_record = false
  route53_zone_id   = ""
  dns_name          = "enclave.staging.zing.you"
  dns_ttl           = 300

  tags = {
    Environment = "staging"
    Application = "nautilus-watermark"
    ManagedBy   = "terraform"
  }
}

