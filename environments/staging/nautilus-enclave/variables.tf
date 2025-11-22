variable "aws_profile" {
  description = "AWS profile to use. Leave empty (default) for CI/CD with OIDC authentication. Set to 'zing-staging' for local development."
  type        = string
  default     = ""
}

variable "eif_version" {
  description = "Version/tag of the EIF file to deploy (e.g., commit SHA). Update this when deploying new enclave versions."
  type        = string
  default     = "c39d8af"
}

