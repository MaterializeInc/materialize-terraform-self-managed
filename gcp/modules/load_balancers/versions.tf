terraform {
  required_version = ">= 1.10"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0, < 2.39.0"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 7.22, < 8"
    }
  }
}
