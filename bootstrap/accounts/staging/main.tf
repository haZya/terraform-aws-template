module "github_actions_role" {
  source = "../../modules/github-actions-role"

  app_name           = var.app_name
  github_owner       = var.github_owner
  github_repo        = var.github_repo
  github_environment = local.github_environment
  state_bucket_name  = local.state_bucket_name
  state_key_prefix   = local.state_key_prefix
}
