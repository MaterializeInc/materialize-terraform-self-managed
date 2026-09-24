terraform {
  required_version = ">= 1.10"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # PostgreSQL 18 needs 4.55.0. Below 4.27.0, changing `version` on the
      # flexible server replaces it (destroying the metadata).
      version = ">= 4.55.0, < 4.82.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0, < 3.10.0"
    }
  }
}
