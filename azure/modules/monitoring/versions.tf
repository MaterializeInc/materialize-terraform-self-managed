terraform {
  # Cannot go lower even if the repo floor does: main.tf pins a module tag
  # containing `/`, which Terraform truncated before 1.10 (hashicorp/terraform#35552).
  required_version = ">= 1.10"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.55.0, < 4.82.0"
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
