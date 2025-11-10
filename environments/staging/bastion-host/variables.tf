variable "ssh_public_key" {
  description = "SSH public key for bastion host access"
  type        = string
  sensitive   = true
}

