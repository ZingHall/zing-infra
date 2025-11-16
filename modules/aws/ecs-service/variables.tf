variable "name" {
  description = "ECS Service 名稱"
  type        = string
}

variable "tags" {
  description = "資源標籤"
  type        = map(string)
  default     = {}
}

# Required External Resources
variable "cluster_id" {
  description = "ECS Cluster ID (ARN). Required external cluster; module no longer creates one."
  type        = string
}

variable "alb_security_group_id" {
  description = "ALB Security Group ID（必填）"
  type        = string
}

variable "target_group_arn" {
  description = "ALB Target Group ARN（必填）"
  type        = string
}

variable "execution_role_arn" {
  description = "ECS Task Execution Role ARN（必填，use ecs-role module to create）"
  type        = string
}

variable "task_role_arn" {
  description = "ECS Task Role ARN（必填，use ecs-role module to create）"
  type        = string
}

variable "desired_count" {
  description = "ECS Service 預設任務數量"
  type        = number
  default     = 1
}


variable "vpc_id" {
  description = "ALB 所在 VPC ID"
  type        = string
}


variable "private_subnet_ids" {
  description = "private subnet ID 清單"
  type        = list(string)
}


variable "assign_public_ip" {
  description = "ECS Service ENI 是否分配公網 IP"
  type        = bool
  default     = false
}

variable "container_name" {
  description = "ECS Service 內部 container 名稱"
  type        = string
  default     = "app"
}

variable "container_port" {
  description = "ECS Service 內部 container 監聽的 port"
  type        = number
  default     = 3000
}

variable "task_cpu" {
  description = "ECS Task CPU 單位"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "ECS Task Memory 單位 (MB)"
  type        = number
  default     = 512
}

# Service Connect 配置
variable "service_connect_namespace" {
  description = "Service Connect namespace ARN"
  type        = string
  default     = ""
}

variable "enable_service_connect" {
  description = "是否啟用 Service Connect"
  type        = bool
  default     = false
}

# 部署配置
variable "deployment_maximum_percent" {
  description = "部署時最大任務百分比"
  type        = number
  default     = 200
}

variable "deployment_minimum_healthy_percent" {
  description = "部署時最小健康任務百分比"
  type        = number
  default     = 100
}

# 健康檢查配置
variable "health_check_grace_period_seconds" {
  description = "健康檢查寬限期（秒），0 表示不使用"
  type        = number
  default     = 0
}

# ECS 標籤管理
variable "enable_ecs_managed_tags" {
  description = "是否啟用 ECS 管理的標籤"
  type        = bool
  default     = false
}

variable "propagate_tags" {
  description = "標籤傳播方式：SERVICE, TASK_DEFINITION, 或 NONE"
  type        = string
  default     = "NONE"
}

variable "log_group_name" {
  description = "(Optional) CloudWatch Log Group name used for container awslogs driver. If empty, logging configuration is omitted."
  type        = string
  default     = ""
}
