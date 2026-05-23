### All these variables will be automatically populated by the variable in each environment

variable "AWS_ROLE_NAME" {
  type = string
}

variable "environment" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "keycloak_image_tag" {
  type = string
}

variable "AWS_ECR" {
  type = string
}

variable "region" {
  type = string
}
