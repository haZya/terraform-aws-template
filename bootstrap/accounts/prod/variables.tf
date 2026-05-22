variable "region" {
  description = "AWS region used by the AWS provider."
  type        = string
}

variable "profile" {
  description = "Optional local AWS shared config profile name."
  type        = string
  default     = null
}

variable "aws_account_id" {
  description = "Expected AWS account ID for this bootstrap target account. Used as a provider safety check."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

variable "app_name" {
  description = "Application name used for bootstrap resource names and tags."
  type        = string
  default     = "example-app"
}

variable "github_owner" {
  description = "GitHub repository owner or organization."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name."
  type        = string
}

variable "state_account_id" {
  description = "AWS account ID that owns the shared Terraform state bucket."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.state_account_id))
    error_message = "state_account_id must be a 12-digit AWS account ID."
  }
}

variable "state_bucket_name" {
  description = "Optional explicit S3 bucket name used for Terraform state. Defaults to {app_name}-terraform-state-{state_account_id}."
  type        = string
  default     = null
}
