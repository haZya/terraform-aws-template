terraform {
  backend "s3" {
    bucket       = "configured-after-bootstrap"
    key          = "configured-after-bootstrap/terraform.tfstate"
    region       = "ap-southeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
