variable "name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the enclave instances will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the Auto Scaling Group"
  type        = list(string)
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the enclave endpoints"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "instance_type" {
  description = "EC2 instance type (must support Nitro Enclaves, e.g., m5.xlarge, c5.xlarge)"
  type        = string
  default     = "m5.xlarge"
}

variable "ami_id" {
  description = "AMI ID for the EC2 instances. If not provided, will use latest Amazon Linux 2"
  type        = string
  default     = null
}

variable "key_pair_name" {
  description = "Name of the AWS key pair for SSH access"
  type        = string
  default     = null
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

variable "s3_bucket_name" {
  description = "S3 bucket name where EIF files are stored"
  type        = string
}

variable "s3_bucket_arn" {
  description = "S3 bucket ARN for IAM permissions"
  type        = string
}

variable "eif_version" {
  description = "Version/tag of the EIF file to deploy (e.g., commit SHA)"
  type        = string
  default     = "latest"
}

variable "eif_path" {
  description = "S3 path to the EIF file (relative to bucket root)"
  type        = string
  default     = "eif/staging"
}

variable "enclave_cpu_count" {
  description = "Number of vCPUs to allocate to the enclave"
  type        = number
  default     = 2
}

variable "enclave_memory_mb" {
  description = "Memory in MB to allocate to the enclave"
  type        = number
  default     = 512
}

variable "enclave_port" {
  description = "Port on which the enclave service listens"
  type        = number
  default     = 3000
}

variable "enclave_init_port" {
  description = "Port for enclave initialization endpoints (localhost only)"
  type        = number
  default     = 3001
}

variable "secrets_arns" {
  description = "List of Secrets Manager ARNs that the instance can access"
  type        = list(string)
  default     = []
}

variable "enable_auto_scaling" {
  description = "Enable Auto Scaling based on CloudWatch metrics"
  type        = bool
  default     = true
}

variable "target_cpu_utilization" {
  description = "Target CPU utilization for Auto Scaling (0-100)"
  type        = number
  default     = 70
}

variable "target_memory_utilization" {
  description = "Target memory utilization for Auto Scaling (0-100)"
  type        = number
  default     = 80
}

variable "health_check_grace_period" {
  description = "Health check grace period in seconds"
  type        = number
  default     = 300
}

variable "root_volume_size" {
  description = "Size of the root EBS volume in GB"
  type        = number
  default     = 200
}

variable "root_volume_type" {
  description = "Type of the root EBS volume"
  type        = string
  default     = "gp3"
}

variable "enable_public_ip" {
  description = "Assign public IP to instances"
  type        = bool
  default     = false
}

variable "user_data_extra" {
  description = "Additional user data script content to append"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "create_dns_record" {
  description = "Whether to create a Route53 DNS record"
  type        = bool
  default     = false
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for DNS record"
  type        = string
  default     = ""
}

variable "dns_name" {
  description = "DNS name for the enclave service"
  type        = string
  default     = ""
}

variable "dns_ttl" {
  description = "TTL for the DNS record"
  type        = number
  default     = 300
}

