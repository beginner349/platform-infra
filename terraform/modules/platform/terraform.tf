terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "4.2.1"
    }
  }
}