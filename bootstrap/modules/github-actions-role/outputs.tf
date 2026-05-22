output "role_arn" {
  description = "ARN of the GitHub Actions deployment role."
  value       = module.github_actions_role.arn
}

output "role_name" {
  description = "Name of the GitHub Actions deployment role."
  value       = module.github_actions_role.name
}
