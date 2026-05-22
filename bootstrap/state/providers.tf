provider "aws" {
  region              = var.region
  profile             = var.profile
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      App       = var.app_name
      ManagedBy = "terraform"
      Scope     = "bootstrap-state"
    }
  }
}
