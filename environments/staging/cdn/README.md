# CDN for Staging Environment

This module sets up a CloudFront CDN with S3 backend for the staging environment.

## Domain

- **CDN Domain**: `cdn.staging.zing.you`
- **S3 Bucket**: `zing-staging-static-assets`

## Architecture

- **S3 Bucket**: Stores static assets in `ap-northeast-1`
- **CloudFront Distribution**: Global CDN with custom domain
- **ACM Certificate**: Created in `us-east-1` (required for CloudFront)
- **Route53**: DNS record pointing to CloudFront

## Features

- ✅ Custom domain with HTTPS
- ✅ Automatic HTTP to HTTPS redirect
- ✅ SPA routing support (404 → index.html)
- ✅ Cost-optimized (PriceClass_100: US, Canada, Europe)
- ✅ IPv6 enabled
- ✅ Compression enabled
- ✅ S3 versioning enabled
- ✅ Secure S3 access (Origin Access Control)

## Deployment

### Initial Setup

```bash
cd zing-infra/environments/staging/cdn
terraform init
terraform plan
terraform apply
```

### Upload Static Assets

```bash
# Get the S3 bucket name from outputs
BUCKET=$(terraform output -raw s3_bucket_id)

# Upload files
aws s3 sync ./dist s3://$BUCKET --profile zing-staging

# Invalidate CloudFront cache
DIST_ID=$(terraform output -raw cdn_distribution_id)
aws cloudfront create-invalidation \
  --distribution-id $DIST_ID \
  --paths "/*" \
  --profile zing-staging
```

### Using Terraform to Upload Files

You can also use Terraform to manage file uploads:

```hcl
resource "aws_s3_object" "static_files" {
  for_each = fileset("${path.module}/../../zing-web/out", "**/*")
  
  bucket       = module.cdn.bucket_id
  key          = each.value
  source       = "${path.module}/../../zing-web/out/${each.value}"
  etag         = filemd5("${path.module}/../../zing-web/out/${each.value}")
  content_type = lookup(local.content_types, regex("\\.[^.]+$", each.value), "application/octet-stream")
}

locals {
  content_types = {
    ".html" = "text/html"
    ".css"  = "text/css"
    ".js"   = "application/javascript"
    ".json" = "application/json"
    ".png"  = "image/png"
    ".jpg"  = "image/jpeg"
    ".svg"  = "image/svg+xml"
  }
}
```

## Outputs

- `cdn_url` - CloudFront distribution URL
- `cdn_domain_name` - CloudFront domain name
- `cdn_distribution_id` - Distribution ID for cache invalidation
- `s3_bucket_id` - S3 bucket ID
- `s3_bucket_arn` - S3 bucket ARN
- `custom_domain` - Custom domain name

## Cache Invalidation

After uploading new files, invalidate the CloudFront cache:

```bash
aws cloudfront create-invalidation \
  --distribution-id $(terraform output -raw cdn_distribution_id) \
  --paths "/*" \
  --profile zing-staging
```

Or invalidate specific paths:

```bash
aws cloudfront create-invalidation \
  --distribution-id $(terraform output -raw cdn_distribution_id) \
  --paths "/index.html" "/_next/static/*" \
  --profile zing-staging
```

## Cache Settings

- **Default TTL**: 1 day (86400 seconds) for HTML
- **Max TTL**: 1 year (31536000 seconds)
- **Static Assets**: Consider adding cache behaviors for longer TTL

## Cost Optimization

Currently using `PriceClass_100` which includes:
- United States
- Canada
- Europe

This is the most cost-effective option. If you need global distribution, change `price_class` to `PriceClass_All` in `main.tf`.

## Troubleshooting

### Certificate Validation

The ACM certificate is created in `us-east-1` (required for CloudFront). The DNS validation record is automatically created in Route53.

If certificate validation fails:
1. Check Route53 hosted zone exists: `staging.zing.you`
2. Verify DNS validation record was created
3. Wait for certificate validation (can take 5-30 minutes)

### 404 Errors

The CDN is configured to redirect 404 and 403 errors to `/index.html` for SPA routing. If you're still seeing 404s:
1. Ensure `index.html` exists in S3 bucket root
2. Check CloudFront error pages configuration
3. Verify cache invalidation completed

### HTTPS Not Working

1. Verify ACM certificate is validated
2. Check Route53 A record points to CloudFront
3. Ensure `viewer_protocol_policy` is set to `redirect-to-https`

## Related Modules

- **Network**: Provides Route53 hosted zone
- **CDN Module**: `../../../modules/aws/cdn`
- **ACM Cert Module**: `../../../modules/aws/acm-cert`

