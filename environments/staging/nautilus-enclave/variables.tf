variable "eif_version" {
  description = "Version/tag of the EIF file to deploy (e.g., commit SHA). Update this when deploying new enclave versions."
  type        = string
  default     = "latest"
}

