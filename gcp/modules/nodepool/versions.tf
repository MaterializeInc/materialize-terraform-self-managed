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
      version = ">= 2.10.0, < 2.39.0"
    }
  }
}
