output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.test.name
}

output "vnet_id" {
  description = "The ID of the virtual network"
  value       = module.networking.vnet_id
}

output "vnet_name" {
  description = "The name of the virtual network"
  value       = module.networking.vnet_name
}

output "api_server_subnet_id" {
  description = "The ID of the API server subnet"
  value       = module.networking.api_server_subnet_id
}

output "aks_subnet_id" {
  description = "The ID of the AKS subnet"
  value       = module.networking.aks_subnet_id
}

output "aks_subnet_name" {
  description = "The name of the AKS subnet"
  value       = module.networking.aks_subnet_name
}

output "postgres_subnet_id" {
  description = "The ID of the PostgreSQL subnet"
  value       = module.networking.postgres_subnet_id
}

output "private_dns_zone_id" {
  description = "The ID of the private DNS zone"
  value       = module.networking.private_dns_zone_id
}

output "nat_gateway_id" {
  description = "The ID of the NAT gateway"
  value       = module.networking.nat_gateway_id
}

output "nat_gateway_public_ip" {
  description = "The public IP of the NAT gateway"
  value       = module.networking.nat_gateway_public_ip
}

output "vnet_address_space" {
  description = "The address space of the virtual network"
  value       = module.networking.vnet_address_space
}
