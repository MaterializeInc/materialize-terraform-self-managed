terraform {
  # The repo-wide floor, but this module cannot follow it back down: the module
  # source in main.tf pins a tag whose name contains a `/`, and Terraform
  # truncated the ref there until 1.10 (hashicorp/terraform#35552).
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.22, < 8"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.5.0, < 2.18.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10.0, < 2.39.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0.0, < 3.10.0"
    }
  }
}
