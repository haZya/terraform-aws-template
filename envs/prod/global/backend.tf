terraform {
  backend "s3" {
    bucket       = "configured-at-init"
    key          = "configured-at-init/terraform.tfstate"
    region       = "ap-southeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
