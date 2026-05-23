module "platform" {
  source = "../../modules/platform"

  environment        = "dev"
  AWS_ROLE_NAME      = var.AWS_ROLE_NAME
  domain_name        = var.domain_name
  keycloak_image_tag = var.keycloak_image_tag
  AWS_ECR            = var.AWS_ECR
  region             = var.region
}