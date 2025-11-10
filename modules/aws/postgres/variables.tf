variable "name" {
  description = "RDS 實例名稱前綴"
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL 版本"
  type        = string
}

variable "instance_class" {
  description = "RDS 實例類型"
  type        = string
}

variable "allocated_storage" {
  description = "分配的儲存空間 (GB)"
  type        = number
}

variable "max_allocated_storage" {
  description = "最大自動擴展儲存空間 (GB)"
  type        = number
}

variable "iops" {
  description = "IOPS"
  type        = number
  default     = null
}

variable "storage_encrypted" {
  description = "是否加密儲存"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS 金鑰 ID"
  type        = string
  default     = null
}

variable "db_name" {
  description = "資料庫名稱"
  type        = string
}

variable "db_username" {
  description = "資料庫管理員帳號"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "資料庫管理員密碼"
  type        = string
  sensitive   = true
  default     = "invalid-password"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet ID 清單（至少 2 個不同 AZ）"
  type        = list(string)
}

variable "multi_az" {
  description = "是否啟用 Multi-AZ"
  type        = bool
  default     = false
}

variable "ca_cert_identifier" {
  description = "CA 憑證識別碼"
  type        = string
  default     = null
}

variable "availability_zone" {
  description = "可用區"
  type        = string
  default     = null
}

variable "backup_retention_period" {
  description = "備份保留天數"
  type        = number
  default     = 7
}

variable "backup_target" {
  description = "備份目標"
  type        = string
  default     = "region"
}

variable "blue_green_update" {
  description = "是否啟用藍綠更新"
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "是否立即套用變更"
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "是否啟用刪除保護"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "是否跳過最終快照"
  type        = bool
  default     = false
}

variable "final_snapshot_identifier" {
  description = "最終快照識別碼"
  type        = string
  default     = null
}

variable "auto_minor_version_upgrade" {
  description = "是否自動升級小版本"
  type        = bool
  default     = true
}

variable "allow_major_version_upgrade" {
  description = "是否允許主版本升級"
  type        = bool
  default     = false
}

variable "monitoring_interval" {
  description = "監控間隔 (秒)"
  type        = number
  default     = 0
}

variable "monitoring_role_arn" {
  description = "監控角色 ARN"
  type        = string
  default     = null
}

variable "performance_insights_enabled" {
  description = "是否啟用效能洞察"
  type        = bool
  default     = false
}

//https://docs.aws.amazon.com/zh_tw/AmazonRDS/latest/UserGuide/CHAP_Limits.html
//https://calculator.aws/#/createCalculator/RDSPostgreSQL
//LEAST({DBInstanceClassMemory/9531392}, 5000)
variable "max_connections" {
  description = "The max connections for this RDS instance."
  type        = number
}

variable "log_min_duration_statement" {
  description = "Sets the minimum execution time in milliseconds above which statements will be logged."
  default     = "1000"
}

variable "log_lock_waits" {
  description = "Whether to log lock waits."
  default     = "off"
  validation {
    condition     = contains(["on", "off"], var.log_lock_waits)
    error_message = "log_lock_waits 必須是 'on' 或 'off' 其中之一"
  }
}

variable "log_error_verbosity" {
  description = "The verbosity of the error messages logged to the log file. Valid values: terse, default, verbose"
  default     = "default"
  validation {
    condition     = contains(["terse", "default", "verbose"], var.log_error_verbosity)
    error_message = "log_error_verbosity 必須是 'terse', 'default', 或 'verbose' 其中之一"
  }
}

variable "log_min_error_statement" {
  description = "Sets the minimum execution time in milliseconds above which statements will be logged."
  default     = "ERROR"
}

variable "enabled_cloudwatch_logs_exports" {
  description = "The logs to export to CloudWatch"
  type        = list(string) //valid values: "postgresql", "upgrade"
  default     = []
}

variable "replica_mode" {
  description = "複製模式"
  type        = string
  default     = null //either mounted or open-read-only mode
}

variable "replicate_source_db" {
  description = "複製來源資料庫"
  type        = string
  default     = null
}

variable "accessible_sg_ids" {
  description = "Accessible security group IDs"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "資源標籤"
  type        = map(string)
  default     = {}
}
