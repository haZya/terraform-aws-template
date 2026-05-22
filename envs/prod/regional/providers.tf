provider "aws" {
  region              = var.region
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      App         = var.app_name
      Environment = local.environment
      Region      = var.region
      Scope       = "regional"
      ManagedBy   = "terraform"
    }
  }
}
