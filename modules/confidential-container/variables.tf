variable "name" {
  description = "Name of the ECS cluster and associated resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the ECS instances will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the Auto Scaling Group"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type (must support AMD SEV-SNP: m6a, c6a, or r6a series)"
  type        = string
  default     = "m6a.large"

  validation {
    condition     = can(regex("^(m6a|c6a|r6a)\\..+$", var.instance_type))
    error_message = "Instance type must be from m6a, c6a, or r6a series to support AMD SEV-SNP."
  }
}

variable "ami_id" {
  description = "AMI ID for the EC2 instances. If not provided, will use latest Amazon Linux 2023 or Ubuntu 22.04+ with UEFI boot support"
  type        = string
  default     = null
}

variable "ami_os" {
  description = "Operating system for AMI lookup (amazon-linux-2023 or ubuntu)"
  type        = string
  default     = "amazon-linux-2023"

  validation {
    condition     = contains(["amazon-linux-2023", "ubuntu"], var.ami_os)
    error_message = "ami_os must be either 'amazon-linux-2023' or 'ubuntu'."
  }
}

variable "min_size" {
  description = "Minimum number of instances in the Auto Scaling Group"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of instances in the Auto Scaling Group"
  type        = number
  default     = 3
}

variable "desired_capacity" {
  description = "Desired number of instances in the Auto Scaling Group"
  type        = number
  default     = 1
}

variable "root_volume_size" {
  description = "Size of the root EBS volume in GB"
  type        = number
  default     = 30
}

variable "root_volume_type" {
  description = "Type of the root EBS volume"
  type        = string
  default     = "gp3"
}

variable "root_device_name" {
  description = "Root device name (varies by AMI)"
  type        = string
  default     = "/dev/xvda"
}

variable "container_insights_enabled" {
  description = "Enable CloudWatch Container Insights for the cluster"
  type        = bool
  default     = true
}

variable "service_connect_namespace" {
  description = "Service Connect namespace ARN for the cluster"
  type        = string
  default     = ""
}

variable "health_check_grace_period" {
  description = "Health check grace period in seconds"
  type        = number
  default     = 300
}

variable "protect_from_scale_in" {
  description = "Protect instances from scale-in during deployments"
  type        = bool
  default     = false
}

variable "enable_auto_scaling" {
  description = "Enable Auto Scaling based on CloudWatch metrics"
  type        = bool
  default     = false
}

variable "target_cpu_utilization" {
  description = "Target CPU utilization for Auto Scaling (0-100)"
  type        = number
  default     = 70
}

variable "enable_managed_scaling" {
  description = "Enable ECS managed scaling for the capacity provider"
  type        = bool
  default     = true
}

variable "target_capacity" {
  description = "Target capacity percentage for managed scaling (1-100)"
  type        = number
  default     = 100
}

variable "max_scaling_step_size" {
  description = "Maximum scaling step size for managed scaling"
  type        = number
  default     = 10000
}

variable "min_scaling_step_size" {
  description = "Minimum scaling step size for managed scaling"
  type        = number
  default     = 1
}

variable "base_capacity" {
  description = "Base capacity for the capacity provider strategy"
  type        = number
  default     = 0
}

variable "managed_termination_protection" {
  description = "Enable managed termination protection for the capacity provider"
  type        = bool
  default     = true
}

variable "user_data_extra" {
  description = "Additional user data script content to append"
  type        = string
  default     = ""
}

# mTLS Configuration for Nitro Enclave connectivity
variable "enable_enclave_mtls" {
  description = "Enable mTLS connectivity to Nitro Enclave"
  type        = bool
  default     = false
}

variable "enclave_security_group_ids" {
  description = "List of security group IDs for Nitro Enclave instances (for mTLS connectivity)"
  type        = list(string)
  default     = []
}

variable "enclave_endpoints" {
  description = "List of Nitro Enclave endpoint URLs (host:port) for mTLS connections"
  type        = list(string)
  default     = []
}

variable "mtls_certificate_secrets_arns" {
  description = "List of Secrets Manager ARNs containing mTLS certificates. For ECS as server: use server cert/key/CA. For ECS as client: use client cert/key/CA."
  type        = list(string)
  default     = []
}

variable "mtls_certificate_path" {
  description = "Path on instances where mTLS certificates will be stored"
  type        = string
  default     = "/etc/ecs/mtls"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

