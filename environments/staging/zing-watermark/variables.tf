variable "task_cpu" {
  description = "ECS Task CPU units"
  type        = number
  default     = 512 # 0.5 vCPU
}

variable "task_memory" {
  description = "ECS Task Memory in MB"
  type        = number
  default     = 1024 # 1 GB
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 1
}

variable "image_tag" {
  description = "Docker image tag"
  type        = string
  default     = "latest"
}

variable "secrets_arns" {
  description = "List of Secrets Manager ARNs"
  type        = list(string)
  default     = []
}

variable "ssm_parameter_arns" {
  description = "List of SSM Parameter Store ARNs"
  type        = list(string)
  default     = []
}

variable "mtls_certificate_secrets_arns" {
  description = "List of Secrets Manager ARNs containing mTLS server certificates (for ECS to accept TEE connections)"
  type        = list(string)
  default     = []
}

