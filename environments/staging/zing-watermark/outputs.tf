output "cluster_id" {
  description = "ECS cluster ID"
  value       = module.confidential_cluster.cluster_id
}

output "cluster_arn" {
  description = "ECS cluster ARN"
  value       = module.confidential_cluster.cluster_arn
}

output "cluster_name" {
  description = "ECS cluster name"
  value       = module.confidential_cluster.cluster_name
}

output "service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.watermark.name
}

output "service_arn" {
  description = "ECS service ARN"
  value       = aws_ecs_service.watermark.id
}

output "task_definition_arn" {
  description = "Task definition ARN"
  value       = aws_ecs_task_definition.watermark.arn
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = module.ecr.repository_url
}

output "security_group_id" {
  description = "Security group ID for ECS service"
  value       = module.confidential_cluster.security_group_id
}

output "capacity_provider_name" {
  description = "Capacity provider name"
  value       = module.confidential_cluster.capacity_provider_name
}

