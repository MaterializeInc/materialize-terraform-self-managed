terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0, < 5.101.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0, < 3.3.0"
    }
  }
}
