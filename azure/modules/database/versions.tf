terraform {
  required_version = ">= 1.10"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # Premium SSD v2 (`storage_type`, `storage_iops`, `storage_throughput`)
      # needs 5.4.0. Below 4.27.0, changing `version` on the flexible server
      # replaces it (destroying the metadata).
      version = ">= 5.4.0, < 6.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0, < 3.10.0"
    }
  }
}
