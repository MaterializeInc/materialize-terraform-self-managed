output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnets
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways, keyed by the availability zone each is in, which is the first zone when `single_nat_gateway` is set. With more gateways than zones, each key ends in the gateway's index."
  # The VPC module puts gateway i in public subnet i, whose zone is zone i,
  # wrapping when there are more subnets than zones.
  value = {
    for i, id in module.vpc.natgw_ids :
    (length(module.vpc.natgw_ids) > length(var.availability_zones)
      ? "${element(var.availability_zones, i)}-${i}"
    : element(var.availability_zones, i)) => id
  }
}

output "nat_public_ips" {
  description = "List of public Elastic IPs created for AWS NAT Gateway"
  value       = module.vpc.nat_public_ips
}

output "vpc_endpoints" {
  description = "Map of VPC endpoints created"
  value       = module.vpc_endpoints.endpoints
}
