output "ecs_cluster_id" {
  description = "ECS cluster ID (ARN) passed into module"
  value       = var.cluster_id
}

output "ecs_service_id" {
  description = "ECS service ID"
  value       = aws_ecs_service.this.id
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.this.name
}

output "ecs_service_sg_id" {
  description = "ECS service security group ID"
  value       = aws_security_group.ecs.id
}

output "ecs_service_sg_arn" {
  description = "ECS service security group ARN"
  value       = aws_security_group.ecs.arn
}

output "task_definition_arn" {
  description = "Task definition ARN"
  value       = aws_ecs_task_definition.this.arn
}
