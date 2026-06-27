terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.50"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "4.3.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "3.9.0"
    }
  }
}