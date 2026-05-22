locals {
  role_name        = var.role_name != null ? var.role_name : "${var.app_name}-${var.github_environment}-github-actions"
  state_bucket_arn = "arn:${data.aws_partition.current.partition}:s3:::${var.state_bucket_name}"
}

data "aws_partition" "current" {}

module "github_oidc_provider" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-oidc-provider"
  version = "~> 6.0"

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

module "github_actions_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "~> 6.0"

  name            = local.role_name
  use_name_prefix = false

  enable_github_oidc = true
  oidc_subjects      = ["${var.github_owner}/${var.github_repo}:environment:${var.github_environment}"]

  policies = {
    AdministratorAccess = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AdministratorAccess"
  }

  depends_on = [module.github_oidc_provider]
}

data "aws_iam_policy_document" "github_actions" {
  statement {
    sid = "ReadCallerIdentity"
    actions = [
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }

  statement {
    sid = "GetTerraformStateBucketLocation"
    actions = [
      "s3:GetBucketLocation",
    ]
    resources = [local.state_bucket_arn]
  }

  statement {
    sid = "ListTerraformStateBucketPrefix"
    actions = [
      "s3:ListBucket",
    ]
    resources = [local.state_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.state_key_prefix}/*"]
    }
  }

  statement {
    sid = "UseTerraformStateObjects"
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = ["${local.state_bucket_arn}/${var.state_key_prefix}/*"]
  }

}

resource "aws_iam_role_policy" "github_actions" {
  name   = "${local.role_name}-policy"
  role   = module.github_actions_role.name
  policy = data.aws_iam_policy_document.github_actions.json
}
