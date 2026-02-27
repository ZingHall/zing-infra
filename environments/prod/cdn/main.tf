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
    key            = "cdn.tfstate"
    region         = "ap-northeast-1"
    encrypt        = true
    dynamodb_table = "terraform-lock-table"
    profile        = "zing-prod"
  }
}

# Provider for ACM certificate (must be in us-east-1 for CloudFront)
provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
  profile = "zing-prod"

  default_tags {
    tags = {
      environment = "prod"
      module      = "cdn"
      managed_by  = "terraform"
    }
  }
}

# Default provider for S3 and other resources
provider "aws" {
  region  = "ap-northeast-1"
  profile = "zing-prod"

  default_tags {
    tags = {
      environment = "prod"
      module      = "cdn"
      managed_by  = "terraform"
    }
  }
}

# Get network outputs for hosted zone
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket  = "terraform-zing-prod"
    key     = "network.tfstate"
    region  = "ap-northeast-1"
    profile = "zing-prod"
  }
}

# ACM Certificate for CloudFront (must be in us-east-1)
module "cdn_certificate" {
  source = "../../../modules/aws/acm-cert"
  providers = {
    aws = aws.us_east_1
  }

  domain_name      = "cdn.prod.zing.you"
  hosted_zone_name = data.terraform_remote_state.network.outputs.hosted_zone_name
  description      = "CDN certificate for prod.zing.you"
}

# CDN Module
module "cdn" {
  source = "../../../modules/aws/cdn"

  name        = "zing-prod"
  bucket_name = "zing-prod-static-assets"

  # Custom domain configuration
  custom_domain   = "cdn.prod.zing.you"
  certificate_arn = module.cdn_certificate.cert_arn

  # Security settings
  minimum_protocol_version = "TLSv1.2_2021"
  viewer_protocol_policy   = "redirect-to-https"

  # Performance settings
  price_class         = "PriceClass_100"
  enable_ipv6         = true
  compress            = true
  default_root_object = "index.html"

  # Cache settings
  default_ttl = 86400    # 1 day for HTML
  max_ttl     = 31536000 # 1 year max

  # S3 Configuration
  enable_versioning       = true
  encryption_algorithm    = "AES256"
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # SPA routing support - redirect 404 to index.html
  custom_error_responses = [
    {
      error_code            = 404
      response_code         = 200
      response_page_path    = "/index.html"
      error_caching_min_ttl = 300
    },
    {
      error_code            = 403
      response_code         = 200
      response_page_path    = "/index.html"
      error_caching_min_ttl = 300
    }
  ]

  tags = {
    Environment = "prod"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}

# Route53 DNS Record for CDN
resource "aws_route53_record" "cdn" {
  zone_id = data.terraform_remote_state.network.outputs.hosted_zone_id
  name    = "cdn.prod.zing.you"
  type    = "A"

  alias {
    name                   = module.cdn.cloudfront_distribution_domain_name
    zone_id                = module.cdn.cloudfront_distribution_hosted_zone_id
    evaluate_target_health = false
  }
}
