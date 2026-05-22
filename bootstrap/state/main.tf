data "aws_caller_identity" "current" {}

locals {
  state_bucket_name            = var.state_bucket_name != null ? var.state_bucket_name : "${var.app_name}-terraform-state-${data.aws_caller_identity.current.account_id}"
  trusted_state_principal_arns = distinct(flatten([for access in var.trusted_state_access : access.principal_arns]))
}

resource "aws_s3_bucket" "terraform_state" {
  bucket        = local.state_bucket_name
  force_destroy = var.force_destroy_state_bucket

  tags = {
    Name = local.state_bucket_name
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_iam_policy_document" "terraform_state" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

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
      resources = [aws_s3_bucket.terraform_state.arn]
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
      resources = [aws_s3_bucket.terraform_state.arn]

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
      resources = ["${aws_s3_bucket.terraform_state.arn}/${statement.value.key_prefix}/*"]
    }
  }
}

resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  policy = data.aws_iam_policy_document.terraform_state.json
}
