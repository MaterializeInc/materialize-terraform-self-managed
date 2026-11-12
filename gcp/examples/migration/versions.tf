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
      version = "~> 2.0, < 3.6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0, < 2.18.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1, < 3.10.0"
    }
    deepmerge = {
      source  = "isometry/deepmerge"
      version = "~> 1.0, < 1.4.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "3.0.1"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.13, < 0.15.0"
    }
  }
}
