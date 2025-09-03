provider "google" {
  project = var.project_id
  region  = var.region
}

# Configure kubernetes provider with GKE cluster credentials
data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${module.gke.cluster_endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = "https://${module.gke.cluster_endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
  }
}


locals {
  common_labels = merge(var.labels, {
    managed_by = "terraform"
    module     = "materialize"
  })

  # Disk support configuration
  install_openebs = var.enable_disk_support ? var.disk_support_config.install_openebs : false


  metadata_backend_url = format(
    "postgres://%s:%s@%s:5432/%s?sslmode=disable",
    module.database.users[0].name,
    urlencode(module.database.users[0].password),
    module.database.private_ip,
    var.database_config.database.name
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

# Configure networking infrastructure including VPC, subnets, and CIDR blocks
module "networking" {
  source = "../../modules/networking"

  project_id = var.project_id
  region     = var.region
  prefix     = var.prefix
  subnets    = var.network_config.subnets
}

# Set up Google Kubernetes Engine (GKE) cluster with basic configuration
module "gke" {
  source = "../../modules/gke"

  depends_on = [module.networking]

  project_id   = var.project_id
  region       = var.region
  prefix       = var.prefix
  network_name = module.networking.network_name
  # we only have one subnet, so we can use the first one
  # if multiple subnets are created, we need to use the specific subnet name here
  subnet_name = module.networking.subnets_names[0]
  namespace   = var.materialize_operator_namespace
}

# Create and configure node pool for the GKE cluster with compute resources
module "nodepool" {
  source     = "../../modules/nodepool"
  depends_on = [module.gke]

  prefix                = var.prefix
  region                = var.region
  enable_private_nodes  = var.gke_nodepool_config.enable_private_nodes
  cluster_name          = module.gke.cluster_name
  project_id            = var.project_id
  node_count            = var.gke_nodepool_config.node_count
  min_nodes             = var.gke_nodepool_config.min_nodes
  max_nodes             = var.gke_nodepool_config.max_nodes
  machine_type          = var.gke_nodepool_config.machine_type
  disk_size_gb          = var.gke_nodepool_config.disk_size_gb
  service_account_email = module.gke.service_account_email
  labels                = local.common_labels

  disk_setup_image  = var.disk_setup_image
  enable_disk_setup = var.enable_disk_support
  local_ssd_count   = var.disk_support_config.local_ssd_count
}

# Install OpenEBS for persistent storage management in Kubernetes
module "openebs" {
  source = "../../../kubernetes/modules/openebs"
  depends_on = [
    module.gke,
    module.nodepool
  ]

  install_openebs          = var.disk_support_config.install_openebs
  create_openebs_namespace = var.disk_support_config.create_openebs_namespace
  openebs_namespace        = var.disk_support_config.openebs_namespace
  openebs_version          = var.disk_support_config.openebs_version
}

resource "random_password" "external_login_password_mz_system" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Set up PostgreSQL database instance for Materialize metadata storage
module "database" {
  source     = "../../modules/database"
  depends_on = [module.networking]

  databases = [var.database_config.database]
  # We don't provide password, so random password is generated
  users = [{ name = var.database_config.user_name }]

  project_id = var.project_id
  region     = var.region
  prefix     = var.prefix
  network_id = module.networking.network_id

  tier       = var.database_config.tier
  db_version = var.database_config.version

  labels = local.common_labels
}

# Create Google Cloud Storage bucket for Materialize persistent data storage
module "storage" {
  source = "../../modules/storage"

  project_id      = var.project_id
  region          = var.region
  prefix          = var.prefix
  service_account = module.gke.workload_identity_sa_email
  versioning      = var.storage_config.storage_bucket_versioning
  version_ttl     = var.storage_config.storage_bucket_version_ttl

  labels = local.common_labels
}

# Install cert-manager for SSL certificate management and create cluster issuer
module "certificates" {
  source = "../../../kubernetes/modules/certificates"

  install_cert_manager           = var.cert_manager_config.install_cert_manager
  cert_manager_install_timeout   = var.cert_manager_config.cert_manager_install_timeout
  cert_manager_chart_version     = var.cert_manager_config.cert_manager_chart_version
  use_self_signed_cluster_issuer = var.install_materialize_instance
  cert_manager_namespace         = var.cert_manager_config.cert_manager_namespace
  name_prefix                    = var.prefix

  depends_on = [
    module.gke,
    module.nodepool,
  ]
}

# Install Materialize Kubernetes operator for managing Materialize instances
module "operator" {
  source = "../../modules/operator"

  name_prefix                    = var.prefix
  operator_namespace             = var.materialize_operator_namespace
  use_self_signed_cluster_issuer = var.install_materialize_instance
  region                         = var.region

  depends_on = [
    module.gke,
    module.nodepool,
    module.database,
    module.storage,
    module.certificates,
  ]
}

# Deploy Materialize instance with configured backend connections
module "materialize_instance" {
  count = var.install_materialize_instance ? 1 : 0

  source               = "../../../kubernetes/modules/materialize-instance"
  instance_name        = var.materialize_instance_config.instance_name
  instance_namespace   = var.materialize_instance_config.instance_namespace
  metadata_backend_url = local.metadata_backend_url
  persist_backend_url  = local.persist_backend_url

  # The password for the external login to the Materialize instance
  external_login_password_mz_system = random_password.external_login_password_mz_system.result

  depends_on = [
    module.gke,
    module.database,
    module.storage,
    module.networking,
    module.certificates,
    module.operator,
    module.nodepool,
    module.openebs,
  ]
}

# Configure load balancers for external access to Materialize services
module "load_balancers" {
  count = var.install_materialize_instance ? 1 : 0

  source = "../../modules/load_balancers"

  instance_name = var.materialize_instance_config.instance_name
  namespace     = var.materialize_instance_config.instance_namespace
  resource_id   = module.materialize_instance[0].instance_resource_id

  depends_on = [
    module.materialize_instance,
  ]
}
