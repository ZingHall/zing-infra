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

