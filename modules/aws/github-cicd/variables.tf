variable "repo_owner" {
  description = "GitHub repository owner (deprecated, use repositories instead)"
  type        = string
  default     = ""
}

variable "repo_name" {
  description = "GitHub repository name (deprecated, use repositories instead)"
  type        = string
  default     = ""
}

variable "repositories" {
  description = "List of GitHub repositories in format 'owner/repo'. Example: ['user1/repo1', 'org2/repo2']. Supports wildcards like 'owner/*'"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for repo in var.repositories : can(regex("^[^/]+/[^/]+$", repo))
    ])
    error_message = "Each repository must be in 'owner/repo' format. Wildcards are allowed in repo name (e.g., 'owner/*')."
  }
}

variable "enable_terraform_permissions" {
  description = "是否啟用 Terraform 權限"
  type        = bool
  default     = false
}
