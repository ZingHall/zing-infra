output "ecs_cluster_id" {
  description = "ECS Cluster ID"
  value       = module.ecs_cluster.cluster_id
}

output "ecs_cluster_arn" {
  description = "ECS Cluster ARN"
  value       = module.ecs_cluster.cluster_arn
}

output "ecs_service_id" {
  description = "ECS Service ID"
  value       = aws_ecs_service.indexer.id
}

output "ecs_service_name" {
  description = "ECS Service name"
  value       = aws_ecs_service.indexer.name
}

output "ecs_task_definition_arn" {
  description = "ECS Task Definition ARN"
  value       = aws_ecs_task_definition.indexer.arn
}

output "ecr_repository_url" {
  description = "ECR Repository URL"
  value       = module.ecr.repository_url
}

output "execution_role_arn" {
  description = "ECS Task Execution Role ARN"
  value       = module.ecs_role.execution_role_arn
}

output "task_role_arn" {
  description = "ECS Task Role ARN"
  value       = module.ecs_role.task_role_arn
}

output "log_group_name" {
  description = "CloudWatch Log Group name"
  value       = module.ecs_role.log_group_name
}

output "security_group_id" {
  description = "ECS Service Security Group ID"
  value       = aws_security_group.ecs_indexer.id
}
