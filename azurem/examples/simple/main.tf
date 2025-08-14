provider "azurerm" {
  # Set the Azure subscription ID here or use the ARM_SUBSCRIPTION_ID environment variable
  subscription_id = var.subscription_id

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = false
    }
  }
}

module "networking" {
  source = "../../modules/networking"

  resource_group_name  = var.resource_group_name
  location             = var.location
  prefix               = var.prefix
  vnet_address_space   = var.vnet_address_space
  subnet_cidr          = var.subnet_cidr
  postgres_subnet_cidr = var.postgres_subnet_cidr
}
