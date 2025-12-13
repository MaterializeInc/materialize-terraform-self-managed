terraform {
  required_version = ">= 1.8"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.0"
    }
    deepmerge = {
      source  = "isometry/deepmerge"
      version = "~> 1.0"
    }
  }
}
