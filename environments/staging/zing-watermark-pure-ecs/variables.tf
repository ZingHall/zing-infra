variable "create_mtls_secret" {
  description = "Whether to create a new mTLS secret or use existing one"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

