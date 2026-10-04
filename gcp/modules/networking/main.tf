locals {
  default_route = {
    name              = "${var.prefix}-default-route"
    description       = "route through IGW to access internet"
    destination_range = "0.0.0.0/0"
    tags              = ["egress-inet"]
    next_hop_internet = "true"
  }
  router_name = "${var.prefix}-router"
  routes      = concat(var.routes, [local.default_route])

  # Suffix the name with the CIDR so create_before_destroy doesn't collide
  # when it changes. Unsuffixed when null, for existing deployments.
  private_ip_address_name = var.private_ip_address_cidr == null ? "${var.prefix}-private-ip" : "${var.prefix}-private-ip-${replace(var.private_ip_address_cidr, "/[./]/", "-")}"

  secondary_ranges = {
    for subnet in var.subnets : subnet.name => subnet.secondary_ranges
    if length(subnet.secondary_ranges) > 0
  }
}

module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "18.3.0"

  project_id   = var.project_id
  network_name = "${var.prefix}-network"
  mtu          = var.mtu

  auto_create_subnetworks = false
  # Subnets are regional, so one subnet serves every zone of a multi-zone cluster.
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
  version    = "5.4.0"
  project_id = var.project_id
  region     = var.region

  create_router = var.create_router
  # Only used when the module creates the router.
  router_asn = var.router_asn
  router     = local.router_name
  network    = module.vpc.network_name

  log_config_enable = var.log_config_enable
  # One of ERRORS_ONLY, TRANSLATIONS_ONLY, ALL.
  log_config_filter = var.log_config_filter

  # One of ALL_SUBNETWORKS_ALL_IP_RANGES, ALL_SUBNETWORKS_ALL_PRIMARY_IP_RANGES,
  # LIST_OF_SUBNETWORKS.
  source_subnetwork_ip_ranges_to_nat = var.source_subnetwork_ip_ranges_to_nat

  # Static egress IPs. When non-empty, the module sets nat_ip_allocate_option = "MANUAL_ONLY".
  nat_ips = var.nat_ips
}

resource "google_compute_global_address" "private_ip_address" {
  provider      = google
  project       = var.project_id
  name          = local.private_ip_address_name
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = var.private_ip_address_cidr == null ? null : split("/", var.private_ip_address_cidr)[0]
  prefix_length = var.private_ip_address_cidr == null ? 16 : tonumber(split("/", var.private_ip_address_cidr)[1])
  network       = module.vpc.network_id
  labels        = var.labels
  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = length(local.private_ip_address_name) <= 63
      error_message = "Private IP address name \"${local.private_ip_address_name}\" exceeds 63 characters; shorten prefix."
    }
  }

  # When auto-allocating, GCP only avoids ranges that already exist, so the
  # subnets and their secondary ranges must be created first.
  depends_on = [module.vpc]
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
