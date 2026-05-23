terraform {
  required_version = ">= 1.8"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0, < 2.39.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0, < 2.18.0"
    }
    deepmerge = {
      source  = "isometry/deepmerge"
      version = "~> 1.0, < 1.3.0"
    }
  }
}
