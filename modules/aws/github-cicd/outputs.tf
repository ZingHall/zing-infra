output "role_arn" {
  description = "GitHub Actions IAM Role ARN"
  value       = aws_iam_role.github_actions_cicd.arn
}

output "role_id" {
  description = "GitHub Actions IAM Role ID"
  value       = aws_iam_role.github_actions_cicd.id
}

output "role_name" {
  description = "GitHub Actions IAM Role Name"
  value       = aws_iam_role.github_actions_cicd.name
}

output "oidc_provider_arn" {
  description = "GitHub OIDC Provider ARN"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "allowed_repositories" {
  description = "List of allowed GitHub repositories"
  value       = local.repos_list
}
