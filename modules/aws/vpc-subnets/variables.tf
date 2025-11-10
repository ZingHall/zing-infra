variable "azs" {
  description = "要用的 AZ 清單"
  type        = list(string)
}

variable "vpc_cidr" {
  description = "VPC 的 CIDR"
  type        = string
}

variable "name" {
  description = "資源名稱前綴"
  type        = string
}

variable "private_subnet_offset" {
  description = "private subnet 的 offset"
  type        = number
  default     = 100
}

variable "nat_gateway_count" {
  description = "NAT Gateway 數量(很貴，請謹慎設定)"
  type        = number
  default     = 0
}
