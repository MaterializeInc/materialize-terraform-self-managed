locals {
  default_route = {
    name              = "${var.prefix}-default-route"
    description       = "route through IGW to access internet"
    destination_range = "0.0.0.0/0"
    tags              = "egress-inet"
    next_hop_internet = "true"
  }
  router_name = "${var.prefix}-router"
  routes      = concat(var.routes, [local.default_route])


  # Create secondary ranges map for all subnets
  secondary_ranges = {
    for subnet in var.subnets : subnet.name => subnet.secondary_ranges
    if length(subnet.secondary_ranges) > 0
  }
}

module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "11.1.1"

  project_id   = var.project_id
  network_name = "${var.prefix}-network"
  mtu          = var.mtu

  auto_create_subnetworks = false
  subnets = [
    for subnet in var.subnets : {
      subnet_name           = subnet.name
      subnet_ip             = subnet.cidr
      subnet_region         = subnet.region
      subnet_private_access = subnet.private_access
    }
  ]

  secondary_ranges = local.secondary_ranges

  routes = local.routes
}

# Cloud NAT for outbound internet access from private nodes
module "cloud-nat" {
  source     = "terraform-google-modules/cloud-nat/google"
  version    = "5.3.0"
  project_id = var.project_id
  region     = var.region

  # Indicates whether the Cloud Router should be created or not.
  create_router = var.create_router
  # Router ASN, only if router is not passed in and is created by the module.
  router_asn = var.router_asn
  router     = local.router_name
  network    = module.vpc.network_name

  # Indicates whether or not to export logs	
  log_config_enable = var.log_config_enable
  # Specifies the desired filtering of logs on this NAT. Valid values are: 
  # "ERRORS_ONLY", "TRANSLATIONS_ONLY", "ALL"
  log_config_filter = var.log_config_filter

  # How NAT should be configured per Subnetwork. Valid values include:
  # ALL_SUBNETWORKS_ALL_IP_RANGES, ALL_SUBNETWORKS_ALL_PRIMARY_IP_RANGES, LIST_OF_SUBNETWORKS.
  source_subnetwork_ip_ranges_to_nat = var.source_subnetwork_ip_ranges_to_nat
}

resource "google_compute_global_address" "private_ip_address" {
  provider      = google
  project       = var.project_id
  name          = "${var.prefix}-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = module.vpc.network_id
  lifecycle {
    create_before_destroy = true
  }
}

resource "google_service_networking_connection" "private_vpc_connection" {
  provider                = google
  network                 = module.vpc.network_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]

  lifecycle {
    create_before_destroy = true
  }

  deletion_policy = "ABANDON"
}
