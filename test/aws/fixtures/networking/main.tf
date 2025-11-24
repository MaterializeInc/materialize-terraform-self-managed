provider "aws" {
  region  = var.region # Replace with your desired AWS region
  profile = var.profile != null ? var.profile : null
}

module "networking" {
  source = "../../../../aws/modules/networking"

  name_prefix = var.name_prefix
  vpc_cidr    = var.vpc_cidr

  enable_vpc_endpoints = var.enable_vpc_endpoints
  availability_zones   = var.availability_zones
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
  single_nat_gateway   = var.single_nat_gateway
  create_vpc           = var.create_vpc

  tags = var.tags
}
