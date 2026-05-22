locals {
  github_environment = "staging"
  state_bucket_name  = var.state_bucket_name != null ? var.state_bucket_name : "${var.app_name}-terraform-state-${var.state_account_id}"
  state_key_prefix   = "${var.app_name}/staging"
}
