
# NAT Gateway Public IP
resource "azurerm_public_ip" "nat_gateway" {
  name                = "${var.prefix}-nat-gateway-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# NAT Gateway
resource "azurerm_nat_gateway" "main" {
  name                    = "${var.prefix}-nat-gateway"
  location                = var.location
  resource_group_name     = var.resource_group_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = var.nat_gateway_idle_timeout
  tags                    = var.tags
}

# Associate Public IP with NAT Gateway
resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.nat_gateway.id
}

# Network Security Group for AKS subnet
# This NSG will have a default rule to allow all traffic from Loadbalancers in VNet so no need to configure explicitly
# We want this NSG to block all external traffic and only allow traffic within vnet and from Loadbalancers
# https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview#allowazureloadbalancerinbound
resource "azurerm_network_security_group" "aks" {
  name                = "${var.prefix}-aks-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# NSG Rule: Allow Materialize HTTP (port 6876) from VNet only
resource "azurerm_network_security_rule" "materialize_lb_https" {
  name                        = "AllowAzureLBMaterializeHTTPS"
  priority                    = 70
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "6876" # balancerd https port
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = var.aks_subnet_cidr
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.aks.name
}

resource "azurerm_network_security_rule" "materialize_lb_pgwire" {
  name                        = "AllowAzureLBMaterializePgwire"
  priority                    = 80
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "6875" # balancerd sql port
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = var.aks_subnet_cidr
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.aks.name
}

resource "azurerm_network_security_rule" "materialize_lb_health_checks" {
  name                        = "AllowAzureLBMaterializeHealthChecks"
  priority                    = 90
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8080" # balancerd console port
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = var.aks_subnet_cidr
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.aks.name
}

# NSG Rule: Allow Materialize HTTP (port 6876) from VNet only
resource "azurerm_network_security_rule" "materialize_http" {
  name                        = "AllowMaterializeHTTP"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "6876" # balancerd https port
  source_address_prefixes     = [var.vnet_address_space]
  destination_address_prefix  = var.aks_subnet_cidr
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.aks.name
}

# NSG Rule: Allow Materialize pgwire (port 6875) from VNet only
resource "azurerm_network_security_rule" "materialize_pgwire" {
  name                        = "AllowMaterializePgwire"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "6875" # balancerd sql port
  source_address_prefixes     = [var.vnet_address_space]
  destination_address_prefix  = var.aks_subnet_cidr
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.aks.name
}

# NSG Rule: Allow Materialize health checks (port 8080) from VNet only
resource "azurerm_network_security_rule" "materialize_health_checks" {
  name                        = "AllowMaterializeHealthChecks"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8080" # balancerd console port
  source_address_prefixes     = [var.vnet_address_space]
  destination_address_prefix  = var.aks_subnet_cidr
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.aks.name
}

# Virtual Network using Azure Verified Module
module "virtual_network" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.10.0"

  name                = "${var.prefix}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_address_space]
  tags                = var.tags

  subnets = {
    aks = {
      name              = "${var.prefix}-aks-subnet"
      address_prefixes  = [var.aks_subnet_cidr]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql"]
      network_security_group = {
        id = azurerm_network_security_group.aks.id
      }
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
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${var.prefix}-pg-dns-link"
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  resource_group_name   = var.resource_group_name
  virtual_network_id    = module.virtual_network.resource_id
  registration_enabled  = true
  tags                  = var.tags
}
