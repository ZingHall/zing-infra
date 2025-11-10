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

variable "log_group_arn" {
  description = "CloudWatch log group ARN for logging permissions"
  type        = string
  default     = ""
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

