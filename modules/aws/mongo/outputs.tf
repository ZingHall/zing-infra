output "cluster_id" {
  description = "The DocumentDB cluster identifier"
  value       = aws_docdb_cluster.this.id
}

output "cluster_arn" {
  description = "The ARN of the DocumentDB cluster"
  value       = aws_docdb_cluster.this.arn
}

output "cluster_endpoint" {
  description = "The cluster endpoint"
  value       = aws_docdb_cluster.this.endpoint
}

output "cluster_reader_endpoint" {
  description = "The cluster reader endpoint"
  value       = aws_docdb_cluster.this.reader_endpoint
}

output "cluster_port" {
  description = "The port on which the DB accepts connections"
  value       = aws_docdb_cluster.this.port
}

output "cluster_resource_id" {
  description = "The Resource ID of the cluster"
  value       = aws_docdb_cluster.this.cluster_resource_id
}

output "cluster_members" {
  description = "List of cluster members"
  value       = aws_docdb_cluster.this.cluster_members
}

output "cluster_availability_zones" {
  description = "List of cluster availability zones"
  value       = aws_docdb_cluster.this.availability_zones
}

output "instance_ids" {
  description = "List of cluster instance IDs"
  value       = aws_docdb_cluster_instance.this[*].id
}

output "instance_endpoints" {
  description = "List of cluster instance endpoints"
  value       = aws_docdb_cluster_instance.this[*].endpoint
}

output "security_group_id" {
  description = "The ID of the security group"
  value       = aws_security_group.mongodb.id
}

output "security_group_arn" {
  description = "The ARN of the security group"
  value       = aws_security_group.mongodb.arn
}

output "subnet_group_id" {
  description = "The ID of the subnet group"
  value       = aws_docdb_subnet_group.this.id
}

output "subnet_group_arn" {
  description = "The ARN of the subnet group"
  value       = aws_docdb_subnet_group.this.arn
}

output "parameter_group_id" {
  description = "The ID of the parameter group"
  value       = aws_docdb_cluster_parameter_group.this.id
}

output "parameter_group_arn" {
  description = "The ARN of the parameter group"
  value       = aws_docdb_cluster_parameter_group.this.arn
}

output "log_group_name" {
  description = "The name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.mongodb.name
}

output "log_group_arn" {
  description = "The ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.mongodb.arn
}

output "connection_string" {
  description = "MongoDB connection string"
  value       = "mongodb://${var.master_username}:${var.master_password}@${aws_docdb_cluster.this.endpoint}:${aws_docdb_cluster.this.port}/?ssl=true&ssl_ca_certs=rds-combined-ca-bundle.pem&replicaSet=rs0&readPreference=secondaryPreferred"
  sensitive   = true
}
