terraform {
  required_version = ">= 1.10"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.75.0, < 4.76.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0, < 3.10.0"
    }
    external = {
      source  = "hashicorp/external"
      version = ">= 2.3.4, < 2.5.0"

    }
  }
}
