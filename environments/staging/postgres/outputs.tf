output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.postgres.rds_endpoint
}

output "rds_port" {
  description = "RDS instance port"
  value       = module.postgres.rds_port
}

output "rds_identifier" {
  description = "RDS instance identifier"
  value       = module.postgres.rds_identifier
}

output "rds_arn" {
  description = "RDS instance ARN"
  value       = module.postgres.rds_arn
}

output "rds_security_group_id" {
  description = "RDS security group ID"
  value       = module.postgres.rds_security_group_id
}

output "rds_subnet_group_name" {
  description = "RDS subnet group name"
  value       = module.postgres.rds_subnet_group_name
}

output "rds_parameter_group_name" {
  description = "RDS parameter group name"
  value       = module.postgres.rds_parameter_group_name
}

output "connection_string" {
  description = "PostgreSQL connection string (without password)"
  value       = "postgresql://${var.db_username}@${module.postgres.rds_endpoint}/${var.db_name}"
  sensitive   = false
}

