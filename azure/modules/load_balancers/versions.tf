terraform {
  required_version = ">= 1.0"

  required_providers {

    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.75.0, < 4.55.0"
    }

    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.45.0, < 3.9.0"
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
