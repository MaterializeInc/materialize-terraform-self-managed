output "vnet_id" {
  value = module.networking.vnet_id
}

output "vnet_name" {
  value = module.networking.vnet_name
}

output "aks_subnet_id" {
  value = module.networking.aks_subnet_id
}

output "postgres_subnet_id" {
  value = module.networking.postgres_subnet_id
}

output "private_dns_zone_id" {
  value = module.networking.private_dns_zone_id
}

output "nat_gateway_id" {
  value = module.networking.nat_gateway_id
}

output "nat_gateway_public_ip" {
  value = module.networking.nat_gateway_public_ip
}

output "vnet_address_space" {
  value = module.networking.vnet_address_space
}

output "resource_group_name" {
  value = module.networking.resource_group_name
}
