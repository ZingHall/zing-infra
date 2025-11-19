output "s3_bucket_name" {
  description = "Name of the S3 bucket storing EIF files"
  value       = aws_s3_bucket.enclave_artifacts.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket storing EIF files"
  value       = aws_s3_bucket.enclave_artifacts.arn
}

output "autoscaling_group_id" {
  description = "ID of the Auto Scaling Group"
  value       = module.nautilus_enclave.autoscaling_group_id
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = module.nautilus_enclave.autoscaling_group_name
}

output "autoscaling_group_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = module.nautilus_enclave.autoscaling_group_arn
}

output "launch_template_id" {
  description = "ID of the Launch Template"
  value       = module.nautilus_enclave.launch_template_id
}

output "security_group_id" {
  description = "ID of the Security Group"
  value       = module.nautilus_enclave.security_group_id
}

output "security_group_arn" {
  description = "ARN of the Security Group"
  value       = module.nautilus_enclave.security_group_arn
}

output "iam_role_arn" {
  description = "ARN of the IAM role for EC2 instances"
  value       = module.nautilus_enclave.iam_role_arn
}

output "iam_role_name" {
  description = "Name of the IAM role for EC2 instances"
  value       = module.nautilus_enclave.iam_role_name
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Log Group"
  value       = module.nautilus_enclave.cloudwatch_log_group_name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch Log Group"
  value       = module.nautilus_enclave.cloudwatch_log_group_arn
}

output "enclave_port" {
  description = "Port on which the enclave service listens"
  value       = module.nautilus_enclave.enclave_port
}

output "enclave_init_port" {
  description = "Port for enclave initialization endpoints"
  value       = module.nautilus_enclave.enclave_init_port
}

output "eif_version" {
  description = "Current EIF version deployed"
  value       = local.eif_version
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.alb.alb_dns_name
}

output "alb_zone_id" {
  description = "ALB Zone ID"
  value       = module.alb.alb_zone_id
}

output "enclave_endpoint" {
  description = "HTTPS endpoint for the enclave service"
  value       = "https://${local.enclave_domain}"
}

output "target_group_arn" {
  description = "Target Group ARN for the enclave service"
  value       = module.alb.target_group_arns["enclave"]
}

