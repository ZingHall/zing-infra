output "rule_name" {
  description = "Name of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.this.name
}

output "rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.this.arn
}

output "rule_id" {
  description = "ID of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.this.id
}

output "task_definition_arn" {
  description = "ARN of the task definition (from CI/CD)"
  value       = data.aws_ecs_task_definition.this.arn
}

output "task_definition_family" {
  description = "Family of the task definition"
  value       = data.aws_ecs_task_definition.this.family
}

output "security_group_id" {
  description = "Security group ID for the task"
  value       = aws_security_group.task.id
}

output "eventbridge_role_arn" {
  description = "ARN of the EventBridge IAM role"
  value       = aws_iam_role.eventbridge.arn
}

output "eventbridge_role_name" {
  description = "Name of the EventBridge IAM role"
  value       = aws_iam_role.eventbridge.name
}

output "schedule_expression" {
  description = "The schedule expression"
  value       = aws_cloudwatch_event_rule.this.schedule_expression
}

output "enabled" {
  description = "Whether the scheduler is enabled"
  value       = var.enabled
}

output "task_family_name" {
  description = "Expected task family name (cron-<name>)"
  value       = "cron-${var.name}"
}
