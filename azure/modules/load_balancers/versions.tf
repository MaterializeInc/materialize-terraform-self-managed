terraform {
  required_version = ">= 1.10"

  required_providers {

    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.55.0, < 4.82.0"
    }

    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.45.0, < 3.11.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0, < 2.39.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0, < 2.18.0"
    }
  }
}
