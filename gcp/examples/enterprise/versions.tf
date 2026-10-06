terraform {
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 8.0, < 9"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 8.0, < 9"
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
      source  = "alekc/kubectl"
      version = "2.4.1"
    }
  }
}
