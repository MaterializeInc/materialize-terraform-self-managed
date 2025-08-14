resource "azurerm_resource_group" "materialize" {
  name     = var.resource_group_name
  location = var.location
}

# NAT Gateway Public IP
resource "azurerm_public_ip" "nat_gateway" {
  name                = "${var.prefix}-nat-gateway-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.materialize.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# NAT Gateway
resource "azurerm_nat_gateway" "main" {
  name                    = "${var.prefix}-nat-gateway"
  location                = var.location
  resource_group_name     = azurerm_resource_group.materialize.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = var.nat_gateway_idle_timeout
  tags                    = var.tags
}

# Associate Public IP with NAT Gateway
resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.nat_gateway.id
}

# Virtual Network using Azure Verified Module
module "virtual_network" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.10.0"

  name                = "${var.prefix}-vnet"
  location            = var.location
  resource_group_name = azurerm_resource_group.materialize.name
  address_space       = [var.vnet_address_space]
  tags                = var.tags

  subnets = {
    aks = {
      name              = "${var.prefix}-aks-subnet"
      address_prefixes  = [var.subnet_cidr]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql"]
      nat_gateway = {
        id = azurerm_nat_gateway.main.id
      }
    }
    postgres = {
      name              = "${var.prefix}-pg-subnet"
      address_prefixes  = [var.postgres_subnet_cidr]
      service_endpoints = ["Microsoft.Storage"]
      delegations = [
        {
          name = "postgres-delegation"
          service_delegation = {
            name = "Microsoft.DBforPostgreSQL/flexibleServers"
            actions = [
              "Microsoft.Network/virtualNetworks/subnets/join/action",
            ]
          }
        }
      ]
    }
  }

  depends_on = [azurerm_nat_gateway_public_ip_association.main]
}

resource "random_id" "dns_zone_suffix" {
  byte_length = 4
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "materialize${random_id.dns_zone_suffix.hex}.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.materialize.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${var.prefix}-pg-dns-link"
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  resource_group_name   = azurerm_resource_group.materialize.name
  virtual_network_id    = module.virtual_network.resource_id
  registration_enabled  = true
  tags                  = var.tags
}
