output "vnet_id" {
  description = "The ID of the VNet"
  value       = module.virtual_network.resource_id
}

output "vnet_name" {
  description = "The name of the VNet"
  value       = module.virtual_network.name
}

output "aks_subnet_id" {
  description = "The ID of the AKS subnet"
  value       = module.virtual_network.subnets["aks"].resource_id
}

output "aks_subnet_name" {
  description = "The name of the AKS subnet"
  value       = module.virtual_network.subnets["aks"].name
}

output "postgres_subnet_id" {
  description = "The ID of the PostgreSQL subnet"
  value       = module.virtual_network.subnets["postgres"].resource_id
}

output "private_dns_zone_id" {
  description = "The ID of the private DNS zone"
  value       = azurerm_private_dns_zone.postgres.id
}

output "vnet_address_space" {
  description = "The address space of the VNet"
  value       = var.vnet_address_space
}

output "nat_gateway_id" {
  description = "The ID of the NAT Gateway"
  value       = azurerm_nat_gateway.main.id
}

output "nat_gateway_public_ip" {
  description = "The public IP address of the NAT Gateway"
  value       = azurerm_public_ip.nat_gateway.ip_address
}

output "api_server_subnet_id" {
  description = "The ID of the API server subnet (null if VNet Integration is not enabled)"
  value       = var.enable_api_server_vnet_integration && var.api_server_subnet_cidr != null ? module.virtual_network.subnets["apiserver"].resource_id : null
}

output "api_server_subnet_name" {
  description = "The name of the API server subnet (null if VNet Integration is not enabled)"
  value       = var.enable_api_server_vnet_integration && var.api_server_subnet_cidr != null ? module.virtual_network.subnets["apiserver"].name : null
}
