data "aws_caller_identity" "current" {}

locals {
  state_bucket_name            = var.state_bucket_name != null ? var.state_bucket_name : "${var.app_name}-terraform-state-${data.aws_caller_identity.current.account_id}"
  trusted_state_principal_arns = distinct(flatten([for access in var.trusted_state_access : access.principal_arns]))
}

module "terraform_state" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.0"

  bucket        = local.state_bucket_name
  force_destroy = var.force_destroy_state_bucket

  attach_deny_insecure_transport_policy = true
  attach_policy                         = length(var.trusted_state_access) > 0
  policy                                = data.aws_iam_policy_document.terraform_state_access.json

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  versioning = {
    enabled = true
  }

  skip_destroy_public_access_block = false

  tags = {
    Name = local.state_bucket_name
  }
}

data "aws_iam_policy_document" "terraform_state_access" {

  dynamic "statement" {
    for_each = length(local.trusted_state_principal_arns) > 0 ? [1] : []

    content {
      sid    = "AllowTerraformStateBucketLocation"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = local.trusted_state_principal_arns
      }

      actions = [
        "s3:GetBucketLocation",
      ]
      resources = ["_S3_BUCKET_ARN_"]
    }
  }

  dynamic "statement" {
    for_each = { for index, access in var.trusted_state_access : index => access }

    content {
      sid    = "AllowTerraformStateListBucket${statement.key}"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = statement.value.principal_arns
      }

      actions   = ["s3:ListBucket"]
      resources = ["_S3_BUCKET_ARN_"]

      condition {
        test     = "StringLike"
        variable = "s3:prefix"
        values = [
          statement.value.key_prefix,
          "${statement.value.key_prefix}/*",
        ]
      }
    }
  }

  dynamic "statement" {
    for_each = { for index, access in var.trusted_state_access : index => access }

    content {
      sid    = "AllowTerraformStateObjectAccess${statement.key}"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = statement.value.principal_arns
      }

      actions = [
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:PutObject",
      ]
      resources = ["_S3_BUCKET_ARN_/${statement.value.key_prefix}/*"]
    }
  }
}
