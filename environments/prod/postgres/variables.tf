variable "db_name" {
  description = "Database name"
  type        = string
  default     = "zing_db"
}

variable "db_username" {
  description = "Database administrator username"
  type        = string
}

variable "db_password" {
  description = "Database administrator password"
  type        = string
  sensitive   = true
}
