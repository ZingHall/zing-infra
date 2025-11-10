variable "name" {
  description = "Name of the scheduler (task family will be cron-<name>)"
  type        = string
}

variable "description" {
  description = "Description of the scheduler"
  type        = string
  default     = ""
}

variable "schedule_expression" {
  description = "Schedule expression (e.g., 'rate(5 minutes)' or 'cron(0 2 * * ? *)')"
  type        = string

  validation {
    condition     = can(regex("^(rate|cron)\\(.+\\)$", var.schedule_expression))
    error_message = "Schedule expression must be in format 'rate(...)' or 'cron(...)'."
  }
}

variable "enabled" {
  description = "Whether the scheduler is enabled"
  type        = bool
  default     = true
}

# ECS Configuration
variable "cluster_arn" {
  description = "ARN of the ECS cluster"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the task will run"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the task"
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Whether to assign a public IP to the task"
  type        = bool
  default     = false
}

variable "task_count" {
  description = "Number of tasks to run"
  type        = number
  default     = 1

  validation {
    condition     = var.task_count > 0 && var.task_count <= 10
    error_message = "Task count must be between 1 and 10."
  }
}

variable "launch_type" {
  description = "Launch type for the task (FARGATE or EC2)"
  type        = string
  default     = "FARGATE"

  validation {
    condition     = contains(["FARGATE", "EC2"], var.launch_type)
    error_message = "Launch type must be either FARGATE or EC2."
  }
}

variable "platform_version" {
  description = "Fargate platform version"
  type        = string
  default     = "LATEST"
}

variable "capacity_provider_strategy" {
  description = "Capacity provider strategy (for Fargate Spot)"
  type = list(object({
    capacity_provider = string
    weight            = number
    base              = optional(number)
  }))
  default = null
}

variable "task_input" {
  description = "JSON input to pass to the task (for overrides)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
