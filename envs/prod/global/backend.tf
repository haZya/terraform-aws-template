terraform {
  backend "s3" {
    bucket       = "configured-at-init"
    key          = "configured-at-init/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
