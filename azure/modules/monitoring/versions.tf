terraform {
  # The repo-wide floor, but this module cannot follow it back down: the module
  # source in main.tf pins a tag whose name contains a `/`, and Terraform
  # truncated the ref there until 1.10 (hashicorp/terraform#35552).
  required_version = ">= 1.10"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # Upper bound matches the other azure modules so a root composing them
      # resolves a single provider version. The floor is higher than theirs
      # because `azurerm_storage_container` here sets `storage_account_id`,
      # which only exists in 4.x — on a 3.x provider this module does not parse.
      version = ">= 4.0.0, < 4.76.0"
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
