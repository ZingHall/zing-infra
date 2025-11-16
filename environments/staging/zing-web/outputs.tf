output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = module.ecr.repository_url
}

output "ecs_cluster_id" {
  description = "ECS cluster ID"
  value       = module.ecs_cluster.cluster_id
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = module.ecs_cluster.cluster_arn
}

output "ecs_service_id" {
  description = "ECS service ID"
  value       = module.ecs_service.ecs_service_id
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.https_alb.alb_dns_name
}

output "alb_security_group_id" {
  description = "ALB security group ID"
  value       = module.https_alb.alb_security_group_id
}

output "service_endpoint" {
  description = "Service HTTPS endpoint"
  value       = values(module.https_alb.service_endpoints)[0]
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN"
  value       = module.acm_cert.cert_arn
}

output "execution_role_arn" {
  description = "ECS task execution role ARN"
  value       = module.ecs_role.execution_role_arn
}

output "task_role_arn" {
  description = "ECS task role ARN"
  value       = module.ecs_role.task_role_arn
}

output "ecs_service_sg_id" {
  description = "ECS service security group ID"
  value       = module.ecs_service.ecs_service_sg_id
}

