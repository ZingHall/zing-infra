output "bastion_security_group_id" {
  description = "堡壘機安全群組ID"
  value       = module.fck_nat.security_group_id
}

output "nat_route_table_ids" {
  description = "NAT路由表ID列表"
  value       = values(var.private_subnet_route_table_map)
}

output "private_subnet_ids" {
  description = "私有子網ID列表"
  value       = keys(var.private_subnet_route_table_map)
}

output "nat_public_ip" {
  description = "NAT Gateway 公網IP"
  value       = var.allocate_eip ? aws_eip.nat[0].public_ip : module.fck_nat.public_ip
}

output "nat_eip_id" {
  description = "NAT Gateway 彈性IP ID"
  value       = var.allocate_eip ? aws_eip.nat[0].id : null
}

output "nat_dns_name" {
  description = "NAT Gateway DNS名稱"
  value       = var.create_dns_record ? var.dns_name : null
}

output "ssh_connection_command" {
  description = "SSH連線指令"
  value       = "ssh -i ~/.ssh/${var.name}-key.pem ec2-user@${var.allocate_eip ? aws_eip.nat[0].public_ip : module.fck_nat.public_ip}"
}

output "ssh_connection_command_dns" {
  description = "SSH連線指令（使用DNS）"
  value       = var.create_dns_record ? "ssh -i ~/.ssh/${var.name}-key.pem ec2-user@${var.dns_name}" : null
}
