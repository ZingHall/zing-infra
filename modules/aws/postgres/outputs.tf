output "rds_endpoint" {
  description = "RDS 實例的 endpoint"
  value       = aws_db_instance.this.endpoint
}

output "rds_port" {
  description = "RDS 實例的 port"
  value       = aws_db_instance.this.port
}

output "rds_identifier" {
  description = "RDS 實例的 identifier"
  value       = aws_db_instance.this.identifier
}

output "rds_arn" {
  description = "RDS 實例的 ARN"
  value       = aws_db_instance.this.arn
}

output "rds_security_group_id" {
  description = "RDS Security Group ID"
  value       = aws_security_group.rds.id
}

output "rds_subnet_group_name" {
  description = "RDS Subnet Group 名稱"
  value       = aws_db_subnet_group.this.name
}

output "rds_parameter_group_name" {
  description = "RDS Parameter Group 名稱"
  value       = aws_db_parameter_group.this.name
}
