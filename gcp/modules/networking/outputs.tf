output "network_id" {
  description = "The ID of the VPC network"
  value       = module.vpc.network_id
}

output "network_name" {
  description = "The name of the VPC network"
  value       = module.vpc.network_name
}

output "network_self_link" {
  description = "The URI of the VPC network"
  value       = module.vpc.network_self_link
}

output "subnets" {
  description = "A map of subnet outputs"
  value       = module.vpc.subnets
}

output "subnets_names" {
  description = "The names of the subnets"
  value       = module.vpc.subnets_names
}

output "subnets_ids" {
  description = "The IDs of the subnets"
  value       = module.vpc.subnets_ids
}

output "subnets_ips" {
  description = "The IPs and CIDRs of the subnets"
  value       = module.vpc.subnets_ips
}

output "subnets_self_links" {
  description = "The self-links of the subnets"
  value       = module.vpc.subnets_self_links
}

output "subnets_regions" {
  description = "The regions where the subnets are created"
  value       = module.vpc.subnets_regions
}

output "subnets_secondary_ranges" {
  description = "The secondary ranges associated with these subnets"
  value       = module.vpc.subnets_secondary_ranges
}

output "router_name" {
  description = "The name of the Cloud Router"
  value       = module.cloud-nat.router_name
}

output "nat_name" {
  description = "The name of the Cloud NAT"
  value       = module.cloud-nat.name
}

output "nat_region" {
  description = "The region of the Cloud NAT"
  value       = module.cloud-nat.region
}

output "private_vpc_connection" {
  description = "The private VPC connection"
  value       = google_service_networking_connection.private_vpc_connection
}
