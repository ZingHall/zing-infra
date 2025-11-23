variable "aws_profile" {
  description = "AWS profile to use. Leave empty (default) for CI/CD with OIDC authentication. Set to 'zing-staging' for local development."
  type        = string
  default     = ""
}

variable "eif_version" {
  description = "Version/tag of the EIF file to deploy (e.g., commit SHA). Update this when deploying new enclave versions."
  type        = string
  default     = "26d1b39"
}

# Note: create_mtls_client_secret variable removed
# The secret already exists in Secrets Manager and is referenced via data source in certs.tf
# No need to create or manage the secret version in Terraform

