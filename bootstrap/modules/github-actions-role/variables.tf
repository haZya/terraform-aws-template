variable "app_name" {
  description = "Application name used for role naming."
  type        = string
}

variable "github_owner" {
  description = "GitHub repository owner or organization."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name."
  type        = string
}

variable "github_environment" {
  description = "GitHub Environment name allowed to assume this role."
  type        = string
}

variable "role_name" {
  description = "Optional explicit IAM role name."
  type        = string
  default     = null
}

variable "state_bucket_name" {
  description = "S3 bucket name used for Terraform state."
  type        = string
}

variable "state_key_prefix" {
  description = "S3 key prefix this role can use for Terraform state."
  type        = string
}
