terraform {
  required_version = ">= 1.8"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.31, < 7"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    deepmerge = {
      source  = "isometry/deepmerge"
      version = "~> 1.0"
    }
    kubectl = {
      source = "alekc/kubectl"
      # TODO: Unpin once fixed: https://github.com/alekc/terraform-provider-kubectl/issues/283
      version = "~> 2.0, < 2.3"
    }
  }
}
