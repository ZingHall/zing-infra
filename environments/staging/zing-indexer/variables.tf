variable "task_cpu" {
  description = "ECS Task CPU units"
  type        = number
  default     = 512
}

variable "task_memory" {
  description = "ECS Task Memory in MB"
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Number of ECS tasks to run"
  type        = number
  default     = 1
}

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

variable "start_checkpoint" {
  description = "Starting checkpoint for the indexer"
  type        = string
  default     = "0"
}

variable "batch_size" {
  description = "Batch size for processing checkpoints"
  type        = string
  default     = "100"
}

variable "grpc_max_requests" {
  description = "Maximum gRPC requests per window"
  type        = string
  default     = "100"
}

variable "grpc_window_seconds" {
  description = "gRPC rate limit window in seconds"
  type        = string
  default     = "30"
}

variable "log_level" {
  description = "Log level for the indexer"
  type        = string
  default     = "debug"
}

variable "database_url_secret_arn" {
  description = "ARN of Secrets Manager secret containing DATABASE_URL (optional)"
  type        = string
  default     = ""
}

variable "enable_health_check" {
  description = "Enable container health check"
  type        = bool
  default     = true
}

variable "deployment_maximum_percent" {
  description = "Maximum percent of tasks during deployment"
  type        = number
  default     = 200
}

variable "deployment_minimum_healthy_percent" {
  description = "Minimum healthy percent of tasks during deployment"
  type        = number
  default     = 100
}

