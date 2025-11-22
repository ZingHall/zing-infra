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
    # Note: profile cannot be set here (backend config doesn't support variables)
    # For local development, use: terraform init -backend-config="profile=zing-staging"
    # In CI/CD, profile is not needed (OIDC authentication)
    bucket         = "terraform-zing-staging"
    key            = "nautilus-enclave.tfstate"
    region         = "ap-northeast-1"
    encrypt        = true
    dynamodb_table = "terraform-lock-table"
  }
}

provider "aws" {
  region  = "ap-northeast-1"
  profile = var.aws_profile != "" ? var.aws_profile : null

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
    profile = var.aws_profile != "" ? var.aws_profile : null
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

  instance_type = "m5.xlarge"
  # Note: min_size=1, max_size=2, desired_capacity=1 for cost optimization
  # During deployment, CI/CD will temporarily scale to 2 instances for zero-downtime hotswap,
  # then scale back to 1 instance after instance refresh completes.
  # - min_size=1: Minimum instances (normal operation)
  # - max_size=2: Maximum instances (allows scaling to 2 during deployment)
  # - desired_capacity=1: Normal desired capacity (1 instance)
  min_size         = 1
  max_size         = 2
  desired_capacity = 1

  enclave_cpu_count = 2
  enclave_memory_mb = 512
  enclave_port      = 3000
  enclave_init_port = 3001

  # Allow traffic from ALB security group (will be added via security_group_rule)
  allowed_cidr_blocks = []

  secrets_arns = []

  enable_auto_scaling       = true
  target_cpu_utilization    = 70
  target_memory_utilization = 80

  health_check_grace_period = 300

  root_volume_size = 200
  root_volume_type = "gp3"

  enable_public_ip = false

  # Allowed endpoints for vsock-proxy configuration
  # These endpoints will be added to /etc/nitro_enclaves/vsock-proxy.yaml
  # and vsock-proxy processes will be started for each endpoint
  allowed_endpoints = [
    "fullnode.testnet.sui.io",
    "api.weatherapi.com",
    "seal-key-server-testnet-1.mystenlabs.com",
    "seal-key-server-testnet-2.mystenlabs.com"
  ]

  # Deployment configuration (Instance Maintenance Policy)
  # These parameters control instance refresh behavior:
  # - deployment_minimum_healthy_percent: Minimum healthy instances during refresh (MinHealthyPercentage)
  # - deployment_maximum_percent: Maximum instances allowed during refresh (MaxHealthyPercentage)
  # With min=100, max=200: Ensures at least 100% healthy, allows up to 200% capacity during refresh
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  tags = {
    Environment = "staging"
    Application = "nautilus-watermark"
    ManagedBy   = "terraform"
  }
}

# ACM Certificate for Enclave
locals {
  enclave_domain = "enclave.staging.zing.you"
}

module "acm_cert" {
  source = "../../../modules/aws/acm-cert"

  description      = "ACM certificate for ${local.enclave_domain}"
  domain_name      = local.enclave_domain
  hosted_zone_name = data.terraform_remote_state.network.outputs.hosted_zone_name
}

# HTTPS ALB for Enclave
module "alb" {
  source = "../../../modules/aws/https-alb"

  name            = "nautilus-encl"
  vpc_id          = data.terraform_remote_state.network.outputs.vpc_id
  subnet_ids      = data.terraform_remote_state.network.outputs.public_subnet_ids
  certificate_arn = module.acm_cert.cert_arn

  services = [{
    name                             = "enclave"
    port                             = 3000
    target_type                      = "instance" # Required for EC2 Auto Scaling Group
    host_headers                     = [local.enclave_domain]
    priority                         = 100
    health_check_path                = "/health_check"
    health_check_matcher             = "200"
    health_check_interval            = 30
    health_check_timeout             = 5
    health_check_healthy_threshold   = 2
    health_check_unhealthy_threshold = 3
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

# Register Auto Scaling Group with ALB Target Group
resource "aws_autoscaling_attachment" "enclave" {
  autoscaling_group_name = module.nautilus_enclave.autoscaling_group_id
  lb_target_group_arn    = module.alb.target_group_arns["enclave"]
}

# Update Enclave Security Group to allow traffic from ALB
resource "aws_security_group_rule" "enclave_from_alb" {
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  source_security_group_id = module.alb.alb_security_group_id
  security_group_id        = module.nautilus_enclave.security_group_id
  description              = "Allow traffic from ALB to Enclave"
}

# Allow SSH access from VPC for debugging
resource "aws_security_group_rule" "enclave_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [data.terraform_remote_state.network.outputs.vpc_cidr_block]
  security_group_id = module.nautilus_enclave.security_group_id
  description       = "Allow SSH access from VPC"
}

# Route53 Record pointing to ALB
resource "aws_route53_record" "enclave" {
  zone_id = data.terraform_remote_state.network.outputs.hosted_zone_id
  name    = local.enclave_domain
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

