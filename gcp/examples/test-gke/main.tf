# Configure kubernetes provider with GKE cluster credentials
provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${module.gke.cluster_endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
}

module "gke" {
  source = "../../modules/gke"

  project_id   = var.project_id
  region       = var.region
  prefix       = var.prefix
  network_name = var.network_name
  subnet_name  = var.subnet_name
  namespace    = var.namespace
  labels       = var.labels
}

# Conditional nodepool creation
module "nodepool" {
  count      = var.skip_nodepool ? 0 : 1
  source     = "../../modules/nodepool"
  depends_on = [module.gke]

  project_id = var.project_id
  region     = var.region
  prefix     = var.prefix

  enable_private_nodes  = var.enable_private_nodes
  cluster_name          = module.gke.cluster_name
  service_account_email = module.gke.service_account_email
  min_nodes             = var.min_nodes
  max_nodes             = var.max_nodes
  machine_type          = var.materialize_node_type

  labels          = var.labels
  swap_enabled    = var.swap_enabled
  disk_size_gb    = var.disk_size
  local_ssd_count = var.local_ssd_count
}
