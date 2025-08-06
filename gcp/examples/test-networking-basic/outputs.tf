output "network_name" {
  description = "The name of the VPC network"
  value       = module.networking.network_name
}

output "network_id" {
  description = "The ID of the VPC network"
  value       = module.networking.network_id
}

output "subnets" {
  description = "A map of subnet outputs"
  value       = module.networking.subnets
}

output "subnets_names" {
  description = "The names of the subnets"
  value       = module.networking.subnets_names
}

output "subnets_ids" {
  description = "The IDs of the subnets"
  value       = module.networking.subnets_ids
}

output "subnets_ips" {
  description = "The IPs and CIDRs of the subnets"
  value       = module.networking.subnets_ips
}

output "subnets_self_links" {
  description = "The self-links of the subnets"
  value       = module.networking.subnets_self_links
}

output "subnets_regions" {
  description = "The regions where the subnets are created"
  value       = module.networking.subnets_regions
}

output "subnets_secondary_ranges" {
  description = "The secondary ranges associated with these subnets"
  value       = module.networking.subnets_secondary_ranges
}

output "router_name" {
  description = "The name of the Cloud Router"
  value       = module.networking.router_name
}

output "nat_name" {
  description = "The name of the Cloud NAT"
  value       = module.networking.nat_name
}

output "nat_region" {
  description = "The region of the Cloud NAT"
  value       = module.networking.nat_region
}

output "private_vpc_connection" {
  description = "The private VPC connection"
  value       = module.networking.private_vpc_connection
}
