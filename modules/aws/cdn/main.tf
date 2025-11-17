terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# S3 Bucket for static assets
resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name

  tags = merge(var.tags, {
    Name = var.bucket_name
  })
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

# S3 Bucket Server-Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.encryption_algorithm
    }
    bucket_key_enabled = var.bucket_key_enabled
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = var.block_public_acls
  block_public_policy     = var.block_public_policy
  ignore_public_acls      = var.ignore_public_acls
  restrict_public_buckets = var.restrict_public_buckets
}

# S3 Bucket Policy for CloudFront OAC
resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  depends_on = [
    aws_s3_bucket_public_access_block.this,
    aws_cloudfront_origin_access_control.this
  ]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.this.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.this.arn
          }
        }
      }
    ]
  })
}

# CloudFront Origin Access Control (OAC) - modern replacement for OAI
resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.name}-oac"
  description                       = "Origin Access Control for ${var.name} CDN"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "this" {
  enabled             = var.enabled
  is_ipv6_enabled     = var.enable_ipv6
  comment             = var.comment
  default_root_object = var.default_root_object
  price_class         = var.price_class

  aliases = var.custom_domain != null ? [var.custom_domain] : []

  origin {
    domain_name              = aws_s3_bucket.this.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.this.bucket}"
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  default_cache_behavior {
    allowed_methods  = var.allowed_methods
    cached_methods   = var.cached_methods
    target_origin_id = "S3-${aws_s3_bucket.this.bucket}"

    forwarded_values {
      query_string = var.forward_query_string
      cookies {
        forward = var.forward_cookies
      }
    }

    viewer_protocol_policy = var.viewer_protocol_policy
    min_ttl                = var.min_ttl
    default_ttl            = var.default_ttl
    max_ttl                = var.max_ttl
    compress               = var.compress

    trusted_key_groups = var.trusted_key_group_ids != null ? var.trusted_key_group_ids : []
    trusted_signers    = var.trusted_signer_account_ids != null ? var.trusted_signer_account_ids : []
  }

  dynamic "ordered_cache_behavior" {
    for_each = var.cache_behaviors
    content {
      path_pattern           = ordered_cache_behavior.value.path_pattern
      allowed_methods        = ordered_cache_behavior.value.allowed_methods
      cached_methods         = ordered_cache_behavior.value.cached_methods
      target_origin_id       = ordered_cache_behavior.value.target_origin_id
      compress               = lookup(ordered_cache_behavior.value, "compress", var.compress)
      viewer_protocol_policy = lookup(ordered_cache_behavior.value, "viewer_protocol_policy", var.viewer_protocol_policy)

      min_ttl     = lookup(ordered_cache_behavior.value, "min_ttl", var.min_ttl)
      default_ttl = lookup(ordered_cache_behavior.value, "default_ttl", var.default_ttl)
      max_ttl     = lookup(ordered_cache_behavior.value, "max_ttl", var.max_ttl)

      forwarded_values {
        query_string = lookup(ordered_cache_behavior.value, "forward_query_string", var.forward_query_string)
        headers      = lookup(ordered_cache_behavior.value, "forward_headers", [])
        cookies {
          forward = lookup(ordered_cache_behavior.value, "forward_cookies", var.forward_cookies)
        }
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction_type
      locations        = var.geo_restriction_locations
    }
  }

  dynamic "custom_error_response" {
    for_each = var.custom_error_responses
    content {
      error_code            = custom_error_response.value.error_code
      response_code         = lookup(custom_error_response.value, "response_code", null)
      response_page_path    = lookup(custom_error_response.value, "response_page_path", null)
      error_caching_min_ttl = lookup(custom_error_response.value, "error_caching_min_ttl", null)
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.certificate_arn == null && var.custom_domain == null
    acm_certificate_arn            = var.certificate_arn
    ssl_support_method             = var.certificate_arn != null ? "sni-only" : null
    minimum_protocol_version       = var.certificate_arn != null ? var.minimum_protocol_version : null
  }

  dynamic "logging_config" {
    for_each = var.logging_bucket != null ? [1] : []
    content {
      bucket          = var.logging_bucket
      prefix          = var.logging_prefix != null ? var.logging_prefix : ""
      include_cookies = var.logging_include_cookies
    }
  }

  tags = merge(var.tags, {
    Name = var.name
  })

  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront Cache Policy (optional, for modern cache behavior)
resource "aws_cloudfront_cache_policy" "this" {
  count = var.create_cache_policy ? 1 : 0

  name        = "${var.name}-cache-policy"
  comment     = "Cache policy for ${var.name}"
  default_ttl = var.default_ttl
  max_ttl     = var.max_ttl
  min_ttl     = var.min_ttl

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = var.compress
    enable_accept_encoding_gzip   = var.compress

    cookies_config {
      cookie_behavior = var.forward_cookies == "none" ? "none" : "whitelist"
      dynamic "cookies" {
        for_each = var.forward_cookies == "whitelist" && var.forward_cookie_names != null ? [1] : []
        content {
          items = var.forward_cookie_names
        }
      }
    }

    headers_config {
      header_behavior = length(var.forward_headers) > 0 ? "whitelist" : "none"
      dynamic "headers" {
        for_each = length(var.forward_headers) > 0 ? [1] : []
        content {
          items = var.forward_headers
        }
      }
    }

    query_strings_config {
      query_string_behavior = var.forward_query_string ? "all" : "none"
    }
  }
}

