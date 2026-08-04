terraform {
  # `optional()` in object type constraints requires 1.3.
  required_version = ">= 1.3.0"

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
