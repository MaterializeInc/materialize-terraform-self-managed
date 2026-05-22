terraform {
  required_version = ">= 1.8"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0, < 2.39.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0, < 3.3.0"
    }
  }
}
