output "autoscaling_group_id" {
  description = "ID of the Auto Scaling Group"
  value       = aws_autoscaling_group.enclave.id
}

output "autoscaling_group_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.enclave.arn
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.enclave.name
}

output "launch_template_id" {
  description = "ID of the Launch Template"
  value       = aws_launch_template.enclave.id
}

output "launch_template_arn" {
  description = "ARN of the Launch Template"
  value       = aws_launch_template.enclave.arn
}

output "launch_template_latest_version" {
  description = "Latest version of the Launch Template"
  value       = aws_launch_template.enclave.latest_version
}

output "security_group_id" {
  description = "ID of the Security Group"
  value       = aws_security_group.enclave.id
}

output "security_group_arn" {
  description = "ARN of the Security Group"
  value       = aws_security_group.enclave.arn
}

output "iam_role_arn" {
  description = "ARN of the IAM role for EC2 instances"
  value       = aws_iam_role.enclave.arn
}

output "iam_role_name" {
  description = "Name of the IAM role for EC2 instances"
  value       = aws_iam_role.enclave.name
}

output "iam_instance_profile_arn" {
  description = "ARN of the IAM instance profile"
  value       = aws_iam_instance_profile.enclave.arn
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = aws_iam_instance_profile.enclave.name
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.enclave.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.enclave.arn
}

output "enclave_port" {
  description = "Port on which the enclave service listens"
  value       = var.enclave_port
}

output "enclave_init_port" {
  description = "Port for enclave initialization endpoints"
  value       = var.enclave_init_port
}

