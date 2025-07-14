output "network_name" {
  description = "The name of the VPC network"
  value       = module.networking.network_name
}

output "network_id" {
  description = "The ID of the VPC network"
  value       = module.networking.network_id
}

output "subnet_name" {
  description = "The name of the subnet"
  value       = module.networking.subnet_name
}

output "subnet_id" {
  description = "The ID of the subnet"
  value       = module.networking.subnet_id
}

output "router_name" {
  description = "The name of the Cloud Router"
  value       = module.networking.router_name
}

output "nat_name" {
  description = "The name of the Cloud NAT"
  value       = module.networking.nat_name
}

output "private_vpc_connection" {
  description = "The private VPC connection for database connectivity"
  value       = module.networking.private_vpc_connection
}
