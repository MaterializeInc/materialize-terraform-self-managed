provider "azurerm" {
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

module "database" {
  source = "../../../../azurem/modules/database"

  # Database configuration
  databases = var.databases

  # Administrator configuration
  administrator_login    = var.administrator_login
  administrator_password = var.administrator_password

  # Infrastructure configuration
  resource_group_name = var.resource_group_name
  location            = var.location
  prefix              = var.prefix
  subnet_id           = var.subnet_id
  private_dns_zone_id = var.private_dns_zone_id

  # Database server configuration
  sku_name                      = var.sku_name
  postgres_version              = var.postgres_version
  storage_mb                    = var.storage_mb
  backup_retention_days         = var.backup_retention_days
  public_network_access_enabled = var.public_network_access_enabled

  tags = var.tags
}

