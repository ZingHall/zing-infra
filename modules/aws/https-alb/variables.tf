variable "name" {
  description = "Name prefix for ALB and related resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where ALB will be created"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for ALB (typically public subnets)"
  type        = list(string)
}

variable "certificate_arn" {
  description = "Primary ACM certificate ARN for HTTPS listener"
  type        = string
}

variable "services" {
  description = "List of services to create target groups and routing rules for"
  type = list(object({
    name                             = string                 # Service name
    port                             = number                 # Container port
    host_headers                     = list(string)           # Domain names for routing
    priority                         = number                 # Listener rule priority (lower = higher priority)
    target_type                      = optional(string, "ip") # Target type: "ip" for ECS Fargate, "instance" for EC2
    health_check_path                = optional(string, "/health")
    health_check_matcher             = optional(string, "200-399")
    health_check_interval            = optional(number, 30)
    health_check_timeout             = optional(number, 5)
    health_check_healthy_threshold   = optional(number, 2)
    health_check_unhealthy_threshold = optional(number, 2)
    deregistration_delay             = optional(number, 30)
    stickiness_enabled               = optional(bool, false)
    stickiness_duration              = optional(number, 86400)
  }))

  validation {
    condition     = length(var.services) > 0
    error_message = "At least one service must be defined."
  }

  validation {
    condition     = length(var.services) == length(distinct([for s in var.services : s.name]))
    error_message = "Service names must be unique."
  }

  validation {
    condition     = length(var.services) == length(distinct([for s in var.services : s.priority]))
    error_message = "Service priorities must be unique."
  }
}

variable "internal" {
  description = "Whether the ALB is internal or internet-facing"
  type        = bool
  default     = false
}

variable "ingress_cidr_blocks" {
  description = "CIDR blocks allowed to access the ALB"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "http_redirect" {
  description = "Enable HTTP to HTTPS redirect"
  type        = bool
  default     = true
}

variable "ssl_policy" {
  description = "SSL policy for HTTPS listener"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "additional_certificate_arns" {
  description = "Additional ACM certificate ARNs for multi-domain support"
  type        = list(string)
  default     = []
}

variable "access_log_bucket" {
  description = "S3 bucket name for ALB access logs (leave empty to disable)"
  type        = string
  default     = ""
}

variable "access_log_prefix" {
  description = "S3 prefix for ALB access logs"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

