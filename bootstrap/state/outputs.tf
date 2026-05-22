output "state_bucket_arn" {
  description = "ARN of the S3 bucket used for Terraform state."
  value       = module.terraform_state.s3_bucket_arn
}

output "state_bucket_name" {
  description = "Name of the S3 bucket used for Terraform state."
  value       = module.terraform_state.s3_bucket_id
}

output "state_bucket_region" {
  description = "AWS region containing the Terraform state bucket."
  value       = var.region
}
