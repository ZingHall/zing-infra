variable "task_cpu" {
  description = "ECS Task CPU units"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "ECS Task Memory in MB"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of ECS tasks to run"
  type        = number
  default     = 1
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
