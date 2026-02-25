output "cdn_url" {
  description = "CloudFront distribution URL"
  value       = module.cdn.cloudfront_distribution_url
}

output "cdn_domain_name" {
  description = "CloudFront distribution domain name"
  value       = module.cdn.cloudfront_distribution_domain_name
}

output "cdn_distribution_id" {
  description = "CloudFront distribution ID (for cache invalidation)"
  value       = module.cdn.cloudfront_distribution_id
}

output "s3_bucket_id" {
  description = "S3 bucket ID for uploading static assets"
  value       = module.cdn.bucket_id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = module.cdn.bucket_arn
}

output "s3_bucket_domain_name" {
  description = "S3 bucket domain name"
  value       = module.cdn.bucket_domain_name
}

output "certificate_arn" {
  description = "ACM certificate ARN"
  value       = module.cdn_certificate.cert_arn
}

output "custom_domain" {
  description = "Custom domain name for CDN"
  value       = "cdn.prod.zing.you"
}
