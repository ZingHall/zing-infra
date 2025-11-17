variable "name" {
  description = "Name prefix for CDN resources"
  type        = string
}

variable "bucket_name" {
  description = "Name of the S3 bucket (must be globally unique)"
  type        = string
}

variable "enabled" {
  description = "Whether the CloudFront distribution is enabled"
  type        = bool
  default     = true
}

variable "comment" {
  description = "Comment for the CloudFront distribution"
  type        = string
  default     = ""
}

variable "default_root_object" {
  description = "The object that CloudFront returns when a request is made to the root URL"
  type        = string
  default     = "index.html"
}

variable "price_class" {
  description = "Price class for CloudFront distribution (PriceClass_All, PriceClass_200, PriceClass_100)"
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.price_class)
    error_message = "Price class must be one of: PriceClass_All, PriceClass_200, PriceClass_100"
  }
}

variable "enable_ipv6" {
  description = "Whether to enable IPv6 for CloudFront distribution"
  type        = bool
  default     = true
}

# S3 Bucket Configuration
variable "enable_versioning" {
  description = "Enable versioning for S3 bucket"
  type        = bool
  default     = true
}

variable "encryption_algorithm" {
  description = "Server-side encryption algorithm (AES256 or aws:kms)"
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "aws:kms"], var.encryption_algorithm)
    error_message = "Encryption algorithm must be AES256 or aws:kms"
  }
}

variable "bucket_key_enabled" {
  description = "Whether to enable bucket key for S3 bucket encryption"
  type        = bool
  default     = false
}

variable "block_public_acls" {
  description = "Whether to block public ACLs for S3 bucket"
  type        = bool
  default     = true
}

variable "block_public_policy" {
  description = "Whether to block public policies for S3 bucket"
  type        = bool
  default     = true
}

variable "ignore_public_acls" {
  description = "Whether to ignore public ACLs for S3 bucket"
  type        = bool
  default     = true
}

variable "restrict_public_buckets" {
  description = "Whether to restrict public buckets for S3 bucket"
  type        = bool
  default     = true
}

# CloudFront Cache Configuration
variable "allowed_methods" {
  description = "List of HTTP methods that CloudFront processes and forwards to your origin"
  type        = list(string)
  default     = ["GET", "HEAD", "OPTIONS"]
}

variable "cached_methods" {
  description = "List of HTTP methods for which CloudFront caches responses"
  type        = list(string)
  default     = ["GET", "HEAD"]
}

variable "forward_query_string" {
  description = "Whether to forward query strings to the origin"
  type        = bool
  default     = false
}

variable "forward_cookies" {
  description = "Whether to forward cookies to the origin (none, all, whitelist)"
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "all", "whitelist"], var.forward_cookies)
    error_message = "Forward cookies must be one of: none, all, whitelist"
  }
}

variable "forward_cookie_names" {
  description = "List of cookie names to forward when forward_cookies is whitelist"
  type        = list(string)
  default     = null
}

variable "forward_headers" {
  description = "List of headers to forward to the origin"
  type        = list(string)
  default     = []
}

variable "viewer_protocol_policy" {
  description = "Protocol that viewers can use to access the content (allow-all, https-only, redirect-to-https)"
  type        = string
  default     = "redirect-to-https"

  validation {
    condition     = contains(["allow-all", "https-only", "redirect-to-https"], var.viewer_protocol_policy)
    error_message = "Viewer protocol policy must be one of: allow-all, https-only, redirect-to-https"
  }
}

variable "min_ttl" {
  description = "Minimum TTL in seconds for cached content"
  type        = number
  default     = 0
}

variable "default_ttl" {
  description = "Default TTL in seconds for cached content"
  type        = number
  default     = 86400
}

variable "max_ttl" {
  description = "Maximum TTL in seconds for cached content"
  type        = number
  default     = 31536000
}

variable "compress" {
  description = "Whether to compress content for viewers that support compression"
  type        = bool
  default     = true
}

# Custom Domain Configuration
variable "custom_domain" {
  description = "Custom domain name for CloudFront distribution (e.g., cdn.example.com)"
  type        = string
  default     = null
}

variable "certificate_arn" {
  description = "ACM certificate ARN for custom domain (must be in us-east-1 region)"
  type        = string
  default     = null
}

variable "minimum_protocol_version" {
  description = "Minimum SSL/TLS protocol version (TLSv1, TLSv1.1_2016, TLSv1.2_2018, TLSv1.2_2019, TLSv1.2_2021, TLSv1.3_2021)"
  type        = string
  default     = "TLSv1.2_2021"

  validation {
    condition = contains([
      "TLSv1",
      "TLSv1.1_2016",
      "TLSv1.2_2018",
      "TLSv1.2_2019",
      "TLSv1.2_2021",
      "TLSv1.3_2021"
    ], var.minimum_protocol_version)
    error_message = "Minimum protocol version must be a valid TLS version"
  }
}

# Geo Restriction
variable "geo_restriction_type" {
  description = "Type of geo restriction (none, whitelist, blacklist)"
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "whitelist", "blacklist"], var.geo_restriction_type)
    error_message = "Geo restriction type must be one of: none, whitelist, blacklist"
  }
}

variable "geo_restriction_locations" {
  description = "List of country codes for geo restriction (ISO 3166-1-alpha-2)"
  type        = list(string)
  default     = []
}

# Signed URLs/Private Content
variable "trusted_key_group_ids" {
  description = "List of CloudFront key group IDs for signed URLs"
  type        = list(string)
  default     = null
}

variable "trusted_signer_account_ids" {
  description = "List of AWS account IDs for signed URLs (legacy)"
  type        = list(string)
  default     = null
}

# Cache Behaviors
variable "cache_behaviors" {
  description = "List of ordered cache behaviors for specific path patterns"
  type = list(object({
    path_pattern           = string
    allowed_methods        = list(string)
    cached_methods         = list(string)
    target_origin_id       = string
    compress               = optional(bool)
    viewer_protocol_policy = optional(string)
    min_ttl                = optional(number)
    default_ttl            = optional(number)
    max_ttl                = optional(number)
    forward_query_string   = optional(bool)
    forward_headers        = optional(list(string))
    forward_cookies        = optional(string)
  }))
  default = []
}

# Custom Error Responses
variable "custom_error_responses" {
  description = "List of custom error responses"
  type = list(object({
    error_code            = number
    response_code         = optional(number)
    response_page_path    = optional(string)
    error_caching_min_ttl = optional(number)
  }))
  default = []
}

# Logging
variable "logging_bucket" {
  description = "S3 bucket name for CloudFront access logs"
  type        = string
  default     = null
}

variable "logging_prefix" {
  description = "Prefix for CloudFront access logs in S3 bucket"
  type        = string
  default     = null
}

variable "logging_include_cookies" {
  description = "Whether to include cookies in CloudFront access logs"
  type        = bool
  default     = false
}

# Cache Policy (Modern CloudFront feature)
variable "create_cache_policy" {
  description = "Whether to create a CloudFront cache policy"
  type        = bool
  default     = false
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

