terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0, < 3.3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0, < 2.18.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0, < 3.10.0"
    }
  }
}
