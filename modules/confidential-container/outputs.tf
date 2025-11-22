output "cluster_id" {
  description = "ECS cluster ID"
  value       = aws_ecs_cluster.this.id
}

output "cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.this.name
}

output "capacity_provider_name" {
  description = "ECS capacity provider name"
  value       = aws_ecs_capacity_provider.this.name
}

output "capacity_provider_arn" {
  description = "ECS capacity provider ARN"
  value       = aws_ecs_capacity_provider.this.arn
}

output "autoscaling_group_name" {
  description = "Auto Scaling Group name"
  value       = aws_autoscaling_group.ecs.name
}

output "autoscaling_group_arn" {
  description = "Auto Scaling Group ARN"
  value       = aws_autoscaling_group.ecs.arn
}

output "launch_template_id" {
  description = "Launch template ID"
  value       = aws_launch_template.ecs.id
}

output "launch_template_arn" {
  description = "Launch template ARN"
  value       = aws_launch_template.ecs.arn
}

output "security_group_id" {
  description = "Security group ID for ECS instances"
  value       = aws_security_group.ecs.id
}

output "iam_role_arn" {
  description = "IAM role ARN for ECS instances"
  value       = aws_iam_role.ecs_instance.arn
}

output "iam_instance_profile_arn" {
  description = "IAM instance profile ARN"
  value       = aws_iam_instance_profile.ecs_instance.arn
}

