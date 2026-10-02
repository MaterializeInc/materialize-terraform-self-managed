terraform {
  required_version = ">= 1.10"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0, < 3.4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0.0, < 3.10.0"
    }
  }
}
