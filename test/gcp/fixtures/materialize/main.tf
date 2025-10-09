# Configure providers
provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_client_config" "default" {}

# GKE Cluster
module "gke" {
  source = "../../../../gcp/modules/gke"

  project_id   = var.project_id
  region       = var.region
  prefix       = var.prefix
  network_name = var.network_name
  subnet_name  = var.subnet_name
  namespace    = var.namespace
  labels       = var.labels
}

# Nodepool creation
module "nodepool" {
  source                = "../../../../gcp/modules/nodepool"
  project_id            = var.project_id
  region                = var.region
  prefix                = var.prefix
  cluster_name          = module.gke.cluster_name
  service_account_email = module.gke.service_account_email

  # Node pool configuration
  machine_type         = var.materialize_node_type
  min_nodes            = var.min_nodes
  max_nodes            = var.max_nodes
  enable_private_nodes = var.enable_private_nodes
  swap_enabled         = var.swap_enabled
  disk_size_gb         = var.disk_size
  local_ssd_count      = var.local_ssd_count
}

# Database
module "database" {
  source = "../../../../gcp/modules/database"

  databases = var.databases
  users     = var.users

  project_id = var.project_id
  network_id = var.network_id
  region     = var.region
  prefix     = var.prefix
  tier       = var.database_tier
  db_version = var.db_version
  labels     = var.labels
}

# Kubernetes provider configuration
provider "kubernetes" {
  host                   = "https://${module.gke.cluster_endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
}

# Helm provider configuration
provider "helm" {
  kubernetes {
    host                   = "https://${module.gke.cluster_endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
  }
}

# Cert Manager
module "cert_manager" {
  source = "../../../../kubernetes/modules/cert-manager"

  install_timeout = var.cert_manager_install_timeout
  chart_version   = var.cert_manager_chart_version
  namespace       = var.cert_manager_namespace

  depends_on = [module.gke]
}

# Self-signed Cluster Issuer
module "self_signed_cluster_issuer" {
  count = var.install_materialize_instance ? 1 : 0

  source = "../../../../kubernetes/modules/self-signed-cluster-issuer"

  name_prefix = var.prefix
  namespace   = var.cert_manager_namespace

  depends_on = [
    module.cert_manager,
  ]
}

# Materialize Operator
module "operator" {
  source = "../../../../gcp/modules/operator"

  region             = var.region
  name_prefix        = var.prefix
  operator_namespace = var.operator_namespace
  swap_enabled       = var.swap_enabled

  depends_on = [module.gke]
}

# Storage (GCS)
module "storage" {
  source = "../../../../gcp/modules/storage"

  project_id      = var.project_id
  region          = var.region
  prefix          = var.prefix
  service_account = module.gke.workload_identity_sa_email

  versioning  = var.storage_bucket_versioning
  version_ttl = var.storage_bucket_version_ttl

  depends_on = [module.gke]
}

# Materialize Instance
module "materialize_instance" {
  count = var.install_materialize_instance ? 1 : 0

  source               = "../../../../kubernetes/modules/materialize-instance"
  instance_name        = var.instance_name
  instance_namespace   = var.instance_namespace
  metadata_backend_url = local.metadata_backend_url
  persist_backend_url  = local.persist_backend_url

  # The password for the external login to the Materialize instance
  external_login_password_mz_system = var.external_login_password_mz_system

  # Materialize license key
  license_key = var.license_key

  # GCP service account annotation for service account
  service_account_annotations = {
    "iam.gke.io/gcp-service-account" = module.gke.workload_identity_sa_email
  }

  issuer_ref = {
    name = module.self_signed_cluster_issuer[0].issuer_name
    kind = "ClusterIssuer"
  }

  depends_on = [
    module.operator,
    module.storage,
    module.self_signed_cluster_issuer,
  ]
}

# Load Balancer
module "load_balancer" {
  count = var.install_materialize_instance ? 1 : 0

  source = "../../../../gcp/modules/load_balancers"

  instance_name = var.instance_name
  namespace     = var.instance_namespace
  resource_id   = module.materialize_instance[0].instance_resource_id

  depends_on = [module.materialize_instance]
}

# Local values for backend URLs
locals {
  metadata_backend_url = format(
    "postgres://%s:%s@%s:5432/%s?sslmode=disable",
    var.user.name,
    urlencode(var.user.password),
    module.database.private_ip,
    module.database.database_names[0]
  )

  encoded_endpoint = urlencode("https://storage.googleapis.com")
  encoded_secret   = urlencode(module.storage.hmac_secret)

  persist_backend_url = format(
    "s3://%s:%s@%s/materialize?endpoint=%s&region=%s",
    module.storage.hmac_access_id,
    local.encoded_secret,
    module.storage.bucket_name,
    local.encoded_endpoint,
    var.region
  )
}
