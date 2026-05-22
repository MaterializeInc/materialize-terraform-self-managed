terraform {
  required_version = ">= 1.0.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10.0, < 2.39.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.5.0, < 2.18.0"
    }
  }
}
