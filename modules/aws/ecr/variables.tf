variable "name" {
  description = "ECR repository 名稱"
  type        = string
}

variable "image_tag_mutability" {
  description = "image tag 是否可變動 (MUTABLE/IMMUTABLE)"
  type        = string
  default     = "IMMUTABLE"
}

variable "scan_on_push" {
  description = "是否啟用 image push 時自動掃描漏洞（基礎版免費）"
  type        = bool
  default     = true
}

variable "count_number" {
  description = "ECR 保留 image 數量上限"
  type        = number
  default     = 10
}

variable "force_delete" {
  description = "是否強制刪除 ECR 倉庫（即使包含映像）"
  type        = bool
  default     = false
}

