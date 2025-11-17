# S3 Bucket Outputs
output "bucket_id" {
  description = "The name (id) of the S3 bucket"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket"
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "The bucket domain name"
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "The bucket region-specific domain name"
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

# CloudFront Outputs
output "cloudfront_distribution_id" {
  description = "The identifier for the CloudFront distribution"
  value       = aws_cloudfront_distribution.this.id
}

output "cloudfront_distribution_arn" {
  description = "The ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.this.arn
}

output "cloudfront_distribution_domain_name" {
  description = "The domain name corresponding to the CloudFront distribution"
  value       = aws_cloudfront_distribution.this.domain_name
}

output "cloudfront_distribution_hosted_zone_id" {
  description = "The CloudFront Route 53 zone ID"
  value       = aws_cloudfront_distribution.this.hosted_zone_id
}

output "cloudfront_distribution_url" {
  description = "The URL of the CloudFront distribution"
  value       = "https://${aws_cloudfront_distribution.this.domain_name}"
}

output "cloudfront_distribution_etag" {
  description = "The current version of the distribution's configuration"
  value       = aws_cloudfront_distribution.this.etag
}

output "cloudfront_distribution_status" {
  description = "The current status of the distribution"
  value       = aws_cloudfront_distribution.this.status
}

# Origin Access Control Outputs
output "origin_access_control_id" {
  description = "The identifier of the CloudFront Origin Access Control"
  value       = aws_cloudfront_origin_access_control.this.id
}

output "origin_access_control_name" {
  description = "The name of the CloudFront Origin Access Control"
  value       = aws_cloudfront_origin_access_control.this.name
}

# Cache Policy Outputs
output "cache_policy_id" {
  description = "The identifier of the CloudFront cache policy"
  value       = var.create_cache_policy ? aws_cloudfront_cache_policy.this[0].id : null
}

