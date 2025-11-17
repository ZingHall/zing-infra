# CDN Module Examples

Quick reference examples for common CDN configurations.

## Minimal Example

```hcl
module "cdn" {
  source = "../../../modules/aws/cdn"

  name        = "my-app"
  bucket_name = "my-app-assets"
}
```

## Next.js Static Export

```hcl
module "cdn" {
  source = "../../../modules/aws/cdn"

  name        = "nextjs-app"
  bucket_name = "nextjs-static-assets"

  # Next.js static files should be cached for 1 year
  cache_behaviors = [
    {
      path_pattern     = "/_next/static/*"
      allowed_methods  = ["GET", "HEAD"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = "S3-nextjs-static-assets"
      min_ttl          = 31536000
      default_ttl      = 31536000
      max_ttl          = 31536000
      forward_query_string = false
      forward_cookies      = "none"
    }
  ]

  # HTML pages should have shorter cache
  default_ttl = 3600  # 1 hour

  # SPA routing support
  custom_error_responses = [
    {
      error_code         = 404
      response_code      = 200
      response_page_path = "/index.html"
    }
  ]
}
```

## React/Vue SPA

```hcl
module "cdn" {
  source = "../../../modules/aws/cdn"

  name        = "spa-app"
  bucket_name = "spa-assets"

  # Redirect all 404s to index.html for client-side routing
  custom_error_responses = [
    {
      error_code         = 404
      response_code      = 200
      response_page_path = "/index.html"
      error_caching_min_ttl = 0
    },
    {
      error_code         = 403
      response_code      = 200
      response_page_path = "/index.html"
      error_caching_min_ttl = 0
    }
  ]

  # Long cache for static assets
  default_ttl = 31536000  # 1 year
}
```

## Custom Domain with Route53

```hcl
# Certificate (must be in us-east-1)
module "cert" {
  source = "../../../modules/aws/acm-cert"

  domain_name      = "cdn.example.com"
  hosted_zone_name = "example.com"
}

# CDN
module "cdn" {
  source = "../../../modules/aws/cdn"

  name            = "example-cdn"
  bucket_name     = "example-assets"
  custom_domain   = "cdn.example.com"
  certificate_arn = module.cert.certificate_arn
}

# Route53 Record
data "aws_route53_zone" "main" {
  name = "example.com"
}

resource "aws_route53_record" "cdn" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "cdn.example.com"
  type    = "A"

  alias {
    name                   = module.cdn.cloudfront_distribution_domain_name
    zone_id                = module.cdn.cloudfront_distribution_hosted_zone_id
    evaluate_target_health = false
  }
}
```

## Multi-Environment Setup

```hcl
# staging/main.tf
module "cdn_staging" {
  source = "../../../modules/aws/cdn"

  name        = "app-staging"
  bucket_name = "app-staging-assets"

  tags = {
    Environment = "staging"
  }
}

# production/main.tf
module "cdn_prod" {
  source = "../../../modules/aws/cdn"

  name        = "app-prod"
  bucket_name = "app-prod-assets"

  custom_domain   = "cdn.example.com"
  certificate_arn = var.prod_cert_arn

  price_class = "PriceClass_All"  # Global for production

  tags = {
    Environment = "production"
  }
}
```

## With Access Logging

```hcl
# Logs bucket
resource "aws_s3_bucket" "cdn_logs" {
  bucket = "cdn-access-logs"
}

resource "aws_s3_bucket_versioning" "cdn_logs" {
  bucket = aws_s3_bucket.cdn_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# CDN with logging
module "cdn" {
  source = "../../../modules/aws/cdn"

  name        = "logged-cdn"
  bucket_name = "app-assets"

  logging_bucket          = aws_s3_bucket.cdn_logs.id
  logging_prefix          = "cloudfront/"
  logging_include_cookies = true
}
```

## Geo-Blocked CDN

```hcl
module "cdn" {
  source = "../../../modules/aws/cdn"

  name        = "restricted-cdn"
  bucket_name = "restricted-assets"

  # Block specific countries
  geo_restriction_type     = "blacklist"
  geo_restriction_locations = ["CN", "RU", "KP", "IR"]
}
```

## Cost-Optimized (US/Europe Only)

```hcl
module "cdn" {
  source = "../../../modules/aws/cdn"

  name        = "cost-optimized"
  bucket_name = "app-assets"

  # Only serve from US, Canada, Europe (cheapest)
  price_class = "PriceClass_100"
}
```

## Media CDN (Images/Videos)

```hcl
module "cdn" {
  source = "../../../modules/aws/cdn"

  name        = "media-cdn"
  bucket_name = "media-assets"

  # Long cache for media
  default_ttl = 31536000  # 1 year

  cache_behaviors = [
    {
      path_pattern     = "*.jpg"
      allowed_methods  = ["GET", "HEAD"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = "S3-media-assets"
      default_ttl       = 31536000
      forward_query_string = false
      forward_cookies      = "none"
    },
    {
      path_pattern     = "*.png"
      allowed_methods  = ["GET", "HEAD"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = "S3-media-assets"
      default_ttl       = 31536000
      forward_query_string = false
      forward_cookies      = "none"
    },
    {
      path_pattern     = "*.mp4"
      allowed_methods  = ["GET", "HEAD"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = "S3-media-assets"
      default_ttl       = 31536000
      forward_query_string = false
      forward_cookies      = "none"
    }
  ]
}
```

## API CDN (No Cache)

```hcl
module "cdn" {
  source = "../../../modules/aws/cdn"

  name        = "api-cdn"
  bucket_name = "api-assets"

  # No cache for API responses
  cache_behaviors = [
    {
      path_pattern     = "/api/*"
      allowed_methods  = ["GET", "HEAD", "OPTIONS", "POST", "PUT", "PATCH", "DELETE"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = "S3-api-assets"
      min_ttl          = 0
      default_ttl      = 0
      max_ttl          = 0
      forward_query_string = true
      forward_headers      = ["Authorization", "Content-Type"]
      forward_cookies      = "all"
    }
  ]
}
```

## Complete Production Setup

```hcl
# Certificate
module "cert" {
  source = "../../../modules/aws/acm-cert"

  domain_name      = "cdn.example.com"
  hosted_zone_name = "example.com"
}

# Logs bucket
resource "aws_s3_bucket" "logs" {
  bucket = "cdn-logs-example"
}

# CDN
module "cdn" {
  source = "../../../modules/aws/cdn"

  name        = "example-prod"
  bucket_name = "example-prod-assets"

  # Custom domain
  custom_domain   = "cdn.example.com"
  certificate_arn = module.cert.certificate_arn

  # Security
  minimum_protocol_version = "TLSv1.2_2021"
  viewer_protocol_policy   = "redirect-to-https"

  # Performance
  price_class = "PriceClass_All"
  enable_ipv6 = true
  compress    = true

  # Caching
  default_ttl = 86400  # 1 day for HTML
  max_ttl     = 31536000  # 1 year max

  # Cache behaviors
  cache_behaviors = [
    {
      path_pattern     = "/static/*"
      allowed_methods  = ["GET", "HEAD"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = "S3-example-prod-assets"
      default_ttl      = 31536000  # 1 year for static
      forward_query_string = false
      forward_cookies      = "none"
    }
  ]

  # Error handling
  custom_error_responses = [
    {
      error_code         = 404
      response_code      = 200
      response_page_path = "/index.html"
    }
  ]

  # Logging
  logging_bucket = aws_s3_bucket.logs.id
  logging_prefix = "cloudfront/"

  # S3 settings
  enable_versioning = true

  tags = {
    Environment = "production"
    Team        = "platform"
  }
}

# Route53
resource "aws_route53_record" "cdn" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "cdn.example.com"
  type    = "A"

  alias {
    name                   = module.cdn.cloudfront_distribution_domain_name
    zone_id                = module.cdn.cloudfront_distribution_hosted_zone_id
    evaluate_target_health = false
  }
}
```

