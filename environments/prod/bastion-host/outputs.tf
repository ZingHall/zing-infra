output "bastion_security_group_id" {
  description = "Bastion host security group ID"
  value       = module.bastion_host.bastion_security_group_id
}

output "nat_public_ip" {
  description = "Bastion host public IP (NAT Gateway)"
  value       = module.bastion_host.nat_public_ip
}

output "nat_eip_id" {
  description = "Bastion host Elastic IP ID"
  value       = module.bastion_host.nat_eip_id
}

output "nat_dns_name" {
  description = "Bastion host DNS name"
  value       = module.bastion_host.nat_dns_name
}

output "ssh_connection_command" {
  description = "SSH connection command"
  value       = module.bastion_host.ssh_connection_command
}

output "ssh_connection_command_dns" {
  description = "SSH connection command (using DNS)"
  value       = module.bastion_host.ssh_connection_command_dns
}

output "nat_route_table_ids" {
  description = "NAT route table IDs"
  value       = module.bastion_host.nat_route_table_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs using NAT"
  value       = module.bastion_host.private_subnet_ids
}
