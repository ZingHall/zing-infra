output "execution_role_arn" {
  description = "ARN of the execution role"
  value       = aws_iam_role.execution.arn
}

output "execution_role_name" {
  description = "Name of the execution role"
  value       = aws_iam_role.execution.name
}

output "execution_role_id" {
  description = "ID of the execution role"
  value       = aws_iam_role.execution.id
}

output "task_role_arn" {
  description = "ARN of the task role"
  value       = aws_iam_role.task.arn
}

output "task_role_name" {
  description = "Name of the task role"
  value       = aws_iam_role.task.name
}

output "task_role_id" {
  description = "ID of the task role"
  value       = aws_iam_role.task.id
}

output "log_group_name" {
  description = "Name of the created CloudWatch Log Group (empty if not created)"
  value       = var.log_group_name
}

output "log_group_arn" {
  description = "ARN of the effective CloudWatch Log Group (created or provided). Empty if none."
  value       = local.effective_log_group_arn
}

