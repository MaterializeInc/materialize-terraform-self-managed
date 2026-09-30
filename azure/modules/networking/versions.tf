terraform {
  required_version = ">= 1.10"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.4.0, < 6.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5, < 3.10.0"
    }
  }
}
