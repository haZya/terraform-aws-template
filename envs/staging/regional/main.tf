module "app" {
  source = "../../../modules/app"

  app_name    = var.app_name
  environment = local.environment
}
