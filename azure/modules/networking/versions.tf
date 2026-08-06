terraform {
  required_version = ">= 1.10"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0, < 4.76.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5, < 3.10.0"
    }
  }
}
