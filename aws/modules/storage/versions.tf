terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0, < 5.101.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0, < 3.9.0"
    }
  }
}
