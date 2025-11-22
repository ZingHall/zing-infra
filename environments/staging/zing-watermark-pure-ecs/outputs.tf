output "cluster_id" {
  description = "ECS cluster ID"
  value       = module.ecs_cluster.cluster_id
}

output "cluster_arn" {
  description = "ECS cluster ARN"
  value       = module.ecs_cluster.cluster_arn
}

output "cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs_cluster.cluster_name
}

output "vpc_id" {
  description = "VPC ID where the cluster can deploy services"
  value       = data.terraform_remote_state.network.outputs.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs for ECS service deployment"
  value       = data.terraform_remote_state.network.outputs.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs for ECS service deployment"
  value       = data.terraform_remote_state.network.outputs.public_subnet_ids
}

output "mtls_secret_arn" {
  description = "ARN of the mTLS certificate secret for ECS services"
  value       = var.create_mtls_secret ? aws_secretsmanager_secret.ecs_server_cert[0].arn : data.aws_secretsmanager_secret.ecs_server_cert[0].arn
}

