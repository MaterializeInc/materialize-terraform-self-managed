provider "google" {
  project = var.project_id
  region  = var.region
}

# Basic networking module test
module "networking" {
  source = "../../modules/networking"

  project_id    = var.project_id
  region        = var.region
  prefix        = var.prefix
  subnet_cidr   = var.subnet_cidr
  pods_cidr     = var.pods_cidr
  services_cidr = var.services_cidr
}