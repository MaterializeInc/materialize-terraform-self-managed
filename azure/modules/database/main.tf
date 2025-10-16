# Generate random password for admin if not provided
resource "random_password" "admin_password" {
  count = var.administrator_password == null || var.administrator_password == "" ? 1 : 0

  length  = 16
  special = true
}

resource "azurerm_postgresql_flexible_server" "postgres" {
  name                = "${var.prefix}-pg"
  resource_group_name = var.resource_group_name
  location            = var.location
  version             = var.postgres_version
  delegated_subnet_id = var.subnet_id
  private_dns_zone_id = var.private_dns_zone_id

  public_network_access_enabled = var.public_network_access_enabled

  administrator_login    = var.administrator_login
  administrator_password = var.administrator_password != null && var.administrator_password != "" ? var.administrator_password : random_password.admin_password[0].result

  storage_mb = var.storage_mb
  sku_name   = var.sku_name

  backup_retention_days = var.backup_retention_days

  lifecycle {
    ignore_changes = [
      zone
    ]
  }

  tags = var.tags
}

# Create multiple databases
resource "azurerm_postgresql_flexible_server_database" "databases" {
  for_each = { for db in var.databases : db.name => db }

  name      = each.value.name
  server_id = azurerm_postgresql_flexible_server.postgres.id
  charset   = each.value.charset
  collation = each.value.collation
}
