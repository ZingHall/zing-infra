# variables.tf

variable "name" {
  description = "The name of the WAF"
  type        = string
}

variable "resource_to_protect_arn" {
  description = "The ARN of the resource to protect (e.g., API Gateway stage or ALB ARN)."
  type        = string
}

# --- Input variables for dynamic rules ---

variable "ip_sets_definition" {
  description = "A map defining multiple IP Sets. The map key will be used as the IP Set's name and reference key."
  type        = map(list(string))
  default     = {}
  /*
  example:
  {
    "office" = ["203.0.113.0/24"],
    "github" = [
      "192.30.252.0/22",
      "185.199.108.0/22",
      "140.82.112.0/20",
      "143.55.64.0/20"
    ]
  }
  */
}

variable "allow_rules" {
  description = "A list of allow rules."
  type = list(object({
    name         = string
    header_names = optional(list(string)) # optional
    ip_set_key   = optional(string)       # optional
    path         = string
    metric_name  = optional(string)
  }))
  default = []
  /*
  example:
  [
    {
      name        = "AllowOfficeToAdmin"
      ip_set_key  = "office" # optional
      path        = "/admin/"
      metric_name = "AllowOfficeToAdmin"
    },
    {
      name        = "AllowGithubWebhook"
      header_names = ["X-Hub-Signature-256"] # optional
      path        = "/webhook/internal/"
      # metric_name is optional. Since it's omitted here, CloudWatch metrics will be disabled for this rule.
    }
  ]
  */
}
