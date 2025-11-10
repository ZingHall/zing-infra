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
  description = "ECS Cluster ID（必填）"
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
