variable "region" {
  description = "AWS region where the Terraform state bucket will be created."
  type        = string
}

variable "profile" {
  description = "Optional local AWS shared config profile name."
  type        = string
  default     = null
}

variable "aws_account_id" {
  description = "Expected AWS account ID for the bootstrap state account. Used as a provider safety check."
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

variable "state_bucket_name" {
  description = "Optional explicit name for the Terraform state bucket. Must be globally unique."
  type        = string
  default     = null

  validation {
    condition     = var.state_bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket_name))
    error_message = "state_bucket_name must be a valid S3 bucket name."
  }
}

variable "force_destroy_state_bucket" {
  description = "Allow Terraform to delete the state bucket even when it contains objects. Keep false for normal use."
  type        = bool
  default     = false
}

variable "trusted_state_access" {
  description = "IAM principals and state key prefixes allowed to access this state bucket."
  type = list(object({
    principal_arns = list(string)
    key_prefix     = string
  }))
  default = []
}
