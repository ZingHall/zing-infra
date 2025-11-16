variable "name" {
  description = "Name prefix for the IAM roles"
  type        = string
}

variable "enable_secrets_access" {
  description = "Enable Secrets Manager and SSM Parameter Store access"
  type        = bool
  default     = false
}

variable "secrets_arns" {
  description = "List of Secrets Manager secret ARNs to grant access to"
  type        = list(string)
  default     = ["*"]
}

variable "ssm_parameter_arns" {
  description = "List of SSM Parameter Store ARNs to grant access to"
  type        = list(string)
  default     = ["*"]
}

variable "log_group_name" {
  description = "(Optional) CloudWatch Log Group name to create. If provided, the module will create the log group and use it for permissions."
  type        = string
  default     = ""
}

variable "log_retention_in_days" {
  description = "Retention in days for the created CloudWatch Log Group (only used when log_group_name is set)."
  type        = number
  default     = 30
}

variable "execution_role_policies" {
  description = "Map of custom policies to attach to execution role (policy name => policy JSON)"
  type        = map(string)
  default     = {}
}

variable "task_role_policies" {
  description = "Map of custom policies to attach to task role (policy name => policy JSON)"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags to apply to IAM roles"
  type        = map(string)
  default     = {}
}

