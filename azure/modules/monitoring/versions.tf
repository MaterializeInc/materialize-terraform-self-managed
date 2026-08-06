terraform {
  # The repo-wide floor, but this module cannot follow it back down: the module
  # source in main.tf pins a tag whose name contains a `/`, and Terraform
  # truncated the ref there until 1.10 (hashicorp/terraform#35552).
  required_version = ">= 1.10"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # Matches the constraint the other azure modules use, so a root that
      # composes them resolves a single provider version.
      version = ">= 3.75.0, < 4.76.0"
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
      version = ">= 3.5.0, < 3.10.0"
    }
  }
}
