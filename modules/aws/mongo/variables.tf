variable "cluster_identifier" {
  type        = string
  description = "The identifier for the DocumentDB cluster"
}

variable "master_username" {
  type        = string
  description = "Username for the master DB user"
  default     = "mongo"
}

variable "master_password" {
  type        = string
  description = "Password for the master DB user"
  default     = "invalid-password"
  sensitive   = true
}

variable "instance_count" {
  type        = number
  description = "Number of instances in the cluster"
  default     = 1
}

variable "instance_class" {
  type        = string
  description = "The instance class to use"
  default     = "db.t3.medium"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the MongoDB cluster will be created"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for the DB subnet group"
}

variable "allowed_security_groups" {
  type        = list(string)
  description = "List of security group IDs allowed to connect to MongoDB"
  default     = []
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "List of CIDR blocks allowed to connect to MongoDB"
  default     = []
}

variable "skip_final_snapshot" {
  type        = bool
  description = "Determines whether a final DB snapshot is created before the DB cluster is deleted"
  default     = false
}

variable "final_snapshot_identifier" {
  type        = string
  description = "The name of the final snapshot when the cluster is deleted"
  default     = null
}

variable "deletion_protection" {
  type        = bool
  description = "If the DB cluster should have deletion protection enabled"
  default     = true
}

variable "backup_retention_period" {
  type        = number
  description = "The number of days to retain backups for"
  default     = 7
}

variable "preferred_backup_window" {
  type        = string
  description = "The daily time range during which automated backups are created"
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  type        = string
  description = "The weekly time range during which system maintenance can occur"
  default     = "sun:04:00-sun:05:00"
}

variable "cluster_parameters" {
  type = list(object({
    name  = string
    value = string
  }))
  description = "List of cluster parameters to apply"
  default     = []
}

variable "log_retention_days" {
  type        = number
  description = "Number of days to retain CloudWatch logs"
  default     = 30
}

variable "tags" {
  type        = map(string)
  description = "A mapping of tags to assign to the resources"
  default     = {}
}
