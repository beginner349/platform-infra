# There is a CI/CD variable named TF_VAR_AWS_ROLE_NAME, it has a TF_VAR_ prefix and terraform will automatically inject its value into this variable
variable "AWS_ROLE_NAME" {
  type        = string
  description = "Automatically populated by GitHub's TF_VAR_AWS_ROLE_NAME"
}

variable "domain_name" {
  type        = string
  description = "The root domain name (e.g., beginner349.com), auto populated by the env variable TF_VAR_domain_name"
}

variable "keycloak_image_tag" {
  type        = string
  description = "The image tag for keycloak, auto populated by the env variable TF_VAR_keycloak_image_tag"
}

variable "AWS_ECR" {
  type        = string
  description = "The name of AWS ECR, auto populated by the env variable TF_VAR_AWS_ECR"
}

variable "region" {
  type        = string
  description = "AWS region, auto populated by the env variable TF_VAR_region"
}
