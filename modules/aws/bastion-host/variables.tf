variable "name" {
  description = "NAT Gateway 名稱"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "公共子網路ID（NAT Gateway 所在子網路）"
  type        = string
}

variable "private_subnet_route_table_map" {
  description = "私有子網ID到路由表ID的映射（子網ID為鍵，路由表ID為值）"
  type        = map(string)
  default     = {}
}

variable "allowed_cidr_blocks" {
  description = "允許SSH存取的CIDR區塊清單"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_public_key" {
  description = "SSH公鑰，用於NAT Gateway存取"
  type        = string
  sensitive   = true
}

variable "instance_type" {
  description = "NAT Gateway 實例類型"
  type        = string
  default     = "t3.nano"
}

variable "additional_security_group_ids" {
  description = "額外安全群組ID"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "資源標籤"
  type        = map(string)
  default     = {}
}

variable "create_dns_record" {
  description = "是否建立DNS記錄"
  type        = bool
  default     = false
}

variable "route53_zone_id" {
  description = "Route53區域ID"
  type        = string
  default     = ""
}

variable "dns_name" {
  description = "DNS記錄名稱"
  type        = string
  default     = ""
}

variable "dns_ttl" {
  description = "DNS記錄TTL"
  type        = string
  default     = "300"
}

variable "allocate_eip" {
  description = "是否分配彈性IP"
  type        = bool
  default     = true
}
