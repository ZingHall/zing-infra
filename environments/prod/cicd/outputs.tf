output "github_actions_cicd_role_arn" {
  value = module.github_cicd.role_arn
}

output "github_actions_cicd_role_id" {
  value = module.github_cicd.role_id
}

output "allowed_repositories" {
  description = "List of allowed GitHub repositories"
  value       = module.github_cicd.allowed_repositories
}
