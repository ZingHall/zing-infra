variable "description" {
  description = "Free form description of this ACM certificate."
  type        = string
}

variable "domain_name" {
  description = "Domain name the certificate is issued for."
  type        = string
}

variable "hosted_zone_name" {
  description = "Need for DNS validation, hosted zone name where record validation will be stored."
  type        = string
}
