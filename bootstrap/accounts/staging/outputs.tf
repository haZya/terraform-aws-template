output "github_actions_role_arn" {
  description = "ARN of the staging GitHub Actions deployment role."
  value       = module.github_actions_role.role_arn
}

output "github_actions_role_name" {
  description = "Name of the staging GitHub Actions deployment role."
  value       = module.github_actions_role.role_name
}
