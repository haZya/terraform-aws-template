variable "region" {
  description = "AWS region to deploy into."
  type        = string
}

variable "profile" {
  description = "Optional local AWS shared config profile name."
  type        = string
  default     = null
}

variable "app_name" {
  description = "Application name used for resource names and tags."
  type        = string
  default     = "example-app"
}

variable "aws_account_id" {
  description = "Expected AWS account ID for this environment. Used as a provider safety check."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}
