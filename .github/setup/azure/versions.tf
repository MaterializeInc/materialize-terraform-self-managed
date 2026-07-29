terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0, < 4.82.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "3.9.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

# Configure the Azure Active Directory Provider
provider "azuread" {
  tenant_id = var.tenant_id
}
