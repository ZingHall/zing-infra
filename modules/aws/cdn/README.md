# CDN Module (S3 + CloudFront)

This module creates a complete CDN solution using AWS S3 for storage and CloudFront for content delivery.

## Features

- ✅ S3 bucket with versioning and encryption
- ✅ CloudFront distribution with Origin Access Control (OAC)
- ✅ Secure S3 access (no public bucket access)
- ✅ Custom domain support with ACM certificates
- ✅ Configurable caching policies
- ✅ IPv6 support
- ✅ Geo-restrictions
- ✅ Custom error pages
- ✅ Access logging
- ✅ Multiple cache behaviors
- ✅ Signed URLs support (optional)

## Usage

### Basic CDN

```hcl
module "cdn" {
  source = "../../../modules/aws/cdn"

  name        = "zing-web"
  bucket_name = "zing-web-static-assets"

  tags = {
    Environment = "production"
    Team        = "platform"
  }
}

# Output the CloudFront URL
output "cdn_url" {
  value = module.cdn.cloudfront_distribution_url
}
```

### CDN with Custom Domain

```hcl
# First, create ACM certificate (must be in us-east-1)
module "cert" {
  source = "../../../modules/aws/acm-cert"

  domain_name       = "cdn.example.com"
  hosted_zone_name  = "example.com"
  description       = "CDN certificate"
}

# Create CDN with custom domain
module "cdn" {
  source = "../../../modules/aws/cdn"

  name        = "zing-web"
  bucket_name = "zing-web-static-assets"
  
  custom_domain   = "cdn.example.com"
  certificate_arn = module.cert.certificate_arn

  tags = var.tags
}

# Create Route53 record
resource "aws_route53_record" "cdn" {
  zone_id = var.hosted_zone_id
  name    = "cdn.example.com"
  type    = "A"

  alias {
    name                   = module.cdn.cloudfront_distribution_domain_name
    zone_id                = module.cdn.cloudfront_distribution_hosted_zone_id
    evaluate_target_health = false
  }
}
```

### CDN with Custom Cache Behaviors

```hcl
module "cdn" {
  source = "../../../modules/aws/cdn"

  name        = "zing-web"
  bucket_name = "zing-web-static-assets"

  # Custom cache behavior for API responses
  cache_behaviors = [
    {
      path_pattern     = "/api/*"
      allowed_methods  = ["GET", "HEAD", "OPTIONS"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = "S3-zing-web-static-assets"
      compress         = true
      min_ttl          = 0
      default_ttl      = 300      # 5 minutes for API
      max_ttl          = 3600
      forward_query_string = true
      forward_headers      = ["Authorization"]
      forward_cookies      = "all"
    },
    {
      path_pattern     = "/static/*"
      allowed_methods  = ["GET", "HEAD", "OPTIONS"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = "S3-zing-web-static-assets"
      compress         = true
      min_ttl          = 86400     # 1 day for static assets
      default_ttl      = 604800    # 1 week
      max_ttl          = 31536000  # 1 year
      forward_query_string = false
      forward_cookies      = "none"
    }
  ]

  tags = var.tags
}
```

### CDN with Geo-Restrictions

```hcl
module "cdn" {
  source = "../../../modules/aws/cdn"

  name        = "zing-web"
  bucket_name = "zing-web-static-assets"

  # Block specific countries
  geo_restriction_type    = "blacklist"
  geo_restriction_locations = ["CN", "RU", "KP"]

  tags = var.tags
}
```

### CDN with Custom Error Pages

```hcl
module "cdn" {
  source = "../../../modules/aws/cdn"

  name        = "zing-web"
  bucket_name = "zing-web-static-assets"

  custom_error_responses = [
    {
      error_code         = 404
      response_code      = 200
      response_page_path = "/index.html"
      error_caching_min_ttl = 300
    },
    {
      error_code         = 403
      response_code      = 200
      response_page_path = "/index.html"
      error_caching_min_ttl = 300
    }
  ]

  tags = var.tags
}
```

### CDN with Access Logging

```hcl
# Create S3 bucket for CloudFront logs
resource "aws_s3_bucket" "logs" {
  bucket = "zing-cdn-logs"
}

module "cdn" {
  source = "../../../modules/aws/cdn"

  name        = "zing-web"
  bucket_name = "zing-web-static-assets"

  logging_bucket          = aws_s3_bucket.logs.id
  logging_prefix          = "cloudfront/"
  logging_include_cookies = true

  tags = var.tags
}
```

### Production-Ready CDN

```hcl
module "cdn" {
  source = "../../../modules/aws/cdn"

  name        = "zing-web-prod"
  bucket_name = "zing-web-prod-assets"

  # Custom domain
  custom_domain   = "cdn.example.com"
  certificate_arn = var.cdn_certificate_arn

  # Security
  minimum_protocol_version = "TLSv1.2_2021"
  viewer_protocol_policy   = "redirect-to-https"

  # Performance
  price_class     = "PriceClass_All"  # Global distribution
  enable_ipv6     = true
  compress        = true
  default_ttl     = 86400    # 1 day
  max_ttl         = 31536000 # 1 year

  # S3 Configuration
  enable_versioning = true
  encryption_algorithm = "AES256"

  # Custom cache behaviors
  cache_behaviors = [
    {
      path_pattern     = "/_next/static/*"
      allowed_methods  = ["GET", "HEAD"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = "S3-zing-web-prod-assets"
      min_ttl          = 31536000  # 1 year for Next.js static files
      default_ttl      = 31536000
      max_ttl          = 31536000
      forward_query_string = false
      forward_cookies      = "none"
    }
  ]

  # Error handling for SPA
  custom_error_responses = [
    {
      error_code         = 404
      response_code      = 200
      response_page_path = "/index.html"
    }
  ]

  # Logging
  logging_bucket = aws_s3_bucket.cdn_logs.id
  logging_prefix = "cloudfront/"

  tags = {
    Environment = "production"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}
```

## Inputs

### Required

| Name | Description | Type |
|------|-------------|------|
| name | Name prefix for CDN resources | string |
| bucket_name | S3 bucket name (globally unique) | string |

### Optional

| Name | Description | Type | Default |
|------|-------------|------|---------|
| enabled | Enable CloudFront distribution | bool | `true` |
| comment | Distribution comment | string | `""` |
| default_root_object | Default root object | string | `"index.html"` |
| price_class | CloudFront price class | string | `"PriceClass_100"` |
| enable_ipv6 | Enable IPv6 | bool | `true` |
| enable_versioning | Enable S3 versioning | bool | `true` |
| encryption_algorithm | S3 encryption (AES256/aws:kms) | string | `"AES256"` |
| block_public_acls | Block public ACLs | bool | `true` |
| allowed_methods | Allowed HTTP methods | list(string) | `["GET", "HEAD", "OPTIONS"]` |
| cached_methods | Cached HTTP methods | list(string) | `["GET", "HEAD"]` |
| forward_query_string | Forward query strings | bool | `false` |
| forward_cookies | Forward cookies (none/all/whitelist) | string | `"none"` |
| viewer_protocol_policy | Viewer protocol policy | string | `"redirect-to-https"` |
| min_ttl | Minimum TTL (seconds) | number | `0` |
| default_ttl | Default TTL (seconds) | number | `86400` |
| max_ttl | Maximum TTL (seconds) | number | `31536000` |
| compress | Enable compression | bool | `true` |
| custom_domain | Custom domain name | string | `null` |
| certificate_arn | ACM certificate ARN (us-east-1) | string | `null` |
| minimum_protocol_version | Minimum TLS version | string | `"TLSv1.2_2021"` |
| geo_restriction_type | Geo restriction type | string | `"none"` |
| geo_restriction_locations | Country codes for restriction | list(string) | `[]` |
| cache_behaviors | Custom cache behaviors | list(object) | `[]` |
| custom_error_responses | Custom error responses | list(object) | `[]` |
| logging_bucket | S3 bucket for access logs | string | `null` |
| logging_prefix | Log prefix | string | `null` |
| tags | Resource tags | map(string) | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| bucket_id | S3 bucket ID |
| bucket_arn | S3 bucket ARN |
| bucket_domain_name | S3 bucket domain name |
| bucket_regional_domain_name | S3 bucket regional domain name |
| cloudfront_distribution_id | CloudFront distribution ID |
| cloudfront_distribution_arn | CloudFront distribution ARN |
| cloudfront_distribution_domain_name | CloudFront domain name |
| cloudfront_distribution_hosted_zone_id | CloudFront Route53 zone ID |
| cloudfront_distribution_url | CloudFront distribution URL |
| cloudfront_distribution_status | Distribution status |
| origin_access_control_id | Origin Access Control ID |

## Deployment Workflow

### 1. Upload Files to S3

```bash
# Sync local directory to S3
aws s3 sync ./dist s3://zing-web-static-assets --delete

# Or use Terraform
resource "aws_s3_object" "static_files" {
  for_each = fileset("${path.module}/dist", "**/*")
  
  bucket       = module.cdn.bucket_id
  key          = each.value
  source       = "${path.module}/dist/${each.value}"
  etag         = filemd5("${path.module}/dist/${each.value}")
  content_type = lookup(local.content_types, regex("\\.[^.]+$", each.value), "application/octet-stream")
}
```

### 2. Invalidate CloudFront Cache

```bash
# After uploading new files
aws cloudfront create-invalidation \
  --distribution-id $(terraform output -raw cloudfront_distribution_id) \
  --paths "/*"
```

## Best Practices

### 1. Security

- ✅ Always use Origin Access Control (OAC) - no public S3 buckets
- ✅ Enable HTTPS-only with redirect
- ✅ Use latest TLS version
- ✅ Block public access to S3 bucket
- ✅ Enable S3 versioning for recovery

### 2. Performance

- ✅ Use appropriate TTL values based on content type
- ✅ Enable compression
- ✅ Use cache behaviors for different content types
- ✅ Choose appropriate price class based on audience

### 3. Cost Optimization

- **PriceClass_100**: US, Canada, Europe (cheapest)
- **PriceClass_200**: Adds Asia, Middle East, Africa
- **PriceClass_All**: Global (most expensive)

### 4. Caching Strategy

```hcl
# Static assets (CSS, JS, images) - long cache
default_ttl = 31536000  # 1 year

# HTML pages - short cache
cache_behaviors = [{
  path_pattern = "*.html"
  default_ttl  = 3600  # 1 hour
}]

# API responses - no cache
cache_behaviors = [{
  path_pattern     = "/api/*"
  default_ttl      = 0
  forward_query_string = true
}]
```

## Common Use Cases

### Single Page Application (SPA)

```hcl
module "cdn" {
  source = "../../../modules/aws/cdn"

  name        = "spa-app"
  bucket_name = "spa-app-assets"

  # Redirect 404 to index.html for client-side routing
  custom_error_responses = [
    {
      error_code         = 404
      response_code      = 200
      response_page_path = "/index.html"
    }
  ]

  tags = var.tags
}
```

### Static Website

```hcl
module "cdn" {
  source = "../../../modules/aws/cdn"

  name        = "static-site"
  bucket_name = "static-site-assets"

  default_root_object = "index.html"
  compress           = true
  default_ttl        = 3600  # 1 hour for HTML

  tags = var.tags
}
```

### Media CDN

```hcl
module "cdn" {
  source = "../../../modules/aws/cdn"

  name        = "media-cdn"
  bucket_name = "media-assets"

  # Long cache for media files
  default_ttl = 31536000  # 1 year

  cache_behaviors = [
    {
      path_pattern     = "*.jpg"
      default_ttl      = 31536000
      target_origin_id = "S3-media-assets"
    },
    {
      path_pattern     = "*.mp4"
      default_ttl      = 31536000
      target_origin_id = "S3-media-assets"
    }
  ]

  tags = var.tags
}
```

## Troubleshooting

### Issue: 403 Forbidden from S3

**Cause**: S3 bucket policy not allowing CloudFront access  
**Solution**: Ensure `origin_access_control_id` is correctly configured and bucket policy allows CloudFront service principal

### Issue: Files not updating after upload

**Cause**: CloudFront cache not invalidated  
**Solution**: Create CloudFront invalidation after uploading new files

### Issue: Custom domain not working

**Cause**: Certificate not in us-east-1 or DNS not configured  
**Solution**: 
1. Ensure ACM certificate is in us-east-1 region
2. Create Route53 A record pointing to CloudFront distribution

### Issue: HTTPS redirect not working

**Cause**: `viewer_protocol_policy` not set correctly  
**Solution**: Set `viewer_protocol_policy = "redirect-to-https"`

## Related Modules

- **`acm-cert`** - Create ACM certificates for custom domains
- **`https-alb`** - Application Load Balancer with HTTPS

## Migration from OAI to OAC

This module uses Origin Access Control (OAC), which is the modern replacement for Origin Access Identity (OAI). OAC provides:

- ✅ Better security with SigV4 signing
- ✅ Support for all S3 operations (not just GET)
- ✅ Better performance
- ✅ Future-proof (OAI is deprecated)

## Cost Considerations

### CloudFront Pricing

- **Data Transfer Out**: ~$0.085/GB (first 10TB)
- **HTTPS Requests**: ~$0.010 per 10,000 requests
- **Invalidation**: First 1,000 paths/month free, then $0.005 per path

### S3 Pricing

- **Storage**: ~$0.023/GB/month
- **PUT Requests**: ~$0.005 per 1,000 requests
- **GET Requests**: ~$0.0004 per 1,000 requests

### Cost Optimization Tips

1. Use appropriate price class for your audience
2. Set long TTLs for static assets to reduce origin requests
3. Enable compression to reduce data transfer
4. Use CloudFront for all static content (cheaper than S3 direct)

## Examples

See usage examples above for common configurations.

