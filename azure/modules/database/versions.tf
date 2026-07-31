terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.75.0, < 5.1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0, < 3.10.0"
    }
  }
}
