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

# NLB Outputs
output "nlb_dns_name" {
  description = "DNS name of the Network Load Balancer"
  value       = aws_lb.watermark_nlb.dns_name
}

output "nlb_arn" {
  description = "ARN of the Network Load Balancer"
  value       = aws_lb.watermark_nlb.arn
}

output "nlb_zone_id" {
  description = "Zone ID of the Network Load Balancer (for Route53 alias)"
  value       = aws_lb.watermark_nlb.zone_id
}

output "target_group_arn" {
  description = "ARN of the Target Group"
  value       = aws_lb_target_group.watermark.arn
}

# Note: NLB doesn't use security groups (Layer 4 load balancer)
# Access control is via VPC routing and ECS security groups

