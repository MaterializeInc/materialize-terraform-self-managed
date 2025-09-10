provider "google" {
  project = var.project_id
  region  = var.region
}

# Basic networking module test
module "networking" {
  source = "../../modules/networking"

  project_id = var.project_id
  region     = var.region
  prefix     = var.prefix
  subnets    = var.subnets
}
