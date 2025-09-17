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
  common_labels = {
    managed_by = "terraform"
    module     = "materialize"
  }

  materialize_operator_namespace = "materialize"
  materialize_instance_namespace = "materialize-environment"
  materialize_instance_name      = "main"


  subnets = [
    {
      name           = "${var.name_prefix}-subnet"
      cidr           = "192.168.0.0/20"
      region         = var.region
      private_access = true
      secondary_ranges = [
        {
          range_name    = "pods"
          ip_cidr_range = "192.168.64.0/18"
        },
        {
          range_name    = "services"
          ip_cidr_range = "192.168.128.0/20"
        }
      ]
    }
  ]

  gke_config = {
    node_count   = 1
    machine_type = "n2-highmem-8"
    disk_size_gb = 100
    min_nodes    = 1
    max_nodes    = 5
  }

  database_config = {
    tier      = "db-custom-2-4096"
    database  = { name = "materialize", charset = "UTF8", collation = "en_US.UTF8" }
    user_name = "materialize"
  }

  # Disk support configuration
  disk_config = {
    enable_disk_setup = true
    local_ssd_count   = 1
    openebs_namespace = "openebs"
  }


  metadata_backend_url = format(
    "postgres://%s:%s@%s:5432/%s?sslmode=disable",
    module.database.users[0].name,
    urlencode(module.database.users[0].password),
    module.database.private_ip,
    local.database_config.database.name
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
  prefix     = var.name_prefix
  subnets    = local.subnets
}

# Set up Google Kubernetes Engine (GKE) cluster with basic configuration
module "gke" {
  source = "../../modules/gke"

  depends_on = [module.networking]

  project_id   = var.project_id
  region       = var.region
  prefix       = var.name_prefix
  network_name = module.networking.network_name
  # we only have one subnet, so we can use the first one
  # if multiple subnets are created, we need to use the specific subnet name here
  subnet_name = module.networking.subnets_names[0]
  namespace   = local.materialize_operator_namespace
}

# Create and configure node pool for the GKE cluster with compute resources
module "nodepool" {
  source     = "../../modules/nodepool"
  depends_on = [module.gke]

  prefix                = var.name_prefix
  region                = var.region
  enable_private_nodes  = true
  cluster_name          = module.gke.cluster_name
  project_id            = var.project_id
  node_count            = local.gke_config.node_count
  min_nodes             = local.gke_config.min_nodes
  max_nodes             = local.gke_config.max_nodes
  machine_type          = local.gke_config.machine_type
  disk_size_gb          = local.gke_config.disk_size_gb
  service_account_email = module.gke.service_account_email
  labels                = local.common_labels

  enable_disk_setup = local.disk_config.enable_disk_setup
  local_ssd_count   = local.disk_config.local_ssd_count
}

# Install OpenEBS for persistent storage management in Kubernetes
module "openebs" {
  source = "../../../kubernetes/modules/openebs"
  depends_on = [
    module.gke,
    module.nodepool
  ]

  install_openebs          = local.disk_config.enable_disk_setup
  create_openebs_namespace = true
  openebs_namespace        = local.disk_config.openebs_namespace
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

  databases = [local.database_config.database]
  # We don't provide password, so random password is generated
  users = [{ name = local.database_config.user_name }]

  project_id = var.project_id
  region     = var.region
  prefix     = var.name_prefix
  network_id = module.networking.network_id

  tier = local.database_config.tier

  labels = local.common_labels
}

# Create Google Cloud Storage bucket for Materialize persistent data storage
module "storage" {
  source = "../../modules/storage"

  project_id      = var.project_id
  region          = var.region
  prefix          = var.name_prefix
  service_account = module.gke.workload_identity_sa_email
  versioning      = false
  version_ttl     = 7

  labels = local.common_labels
}

# Install cert-manager for SSL certificate management and create cluster issuer
module "certificates" {
  source = "../../../kubernetes/modules/certificates"

  install_cert_manager           = true
  use_self_signed_cluster_issuer = var.install_materialize_instance
  cert_manager_namespace         = "cert-manager"
  name_prefix                    = var.name_prefix

  depends_on = [
    module.gke,
    module.nodepool,
  ]
}

# Install Materialize Kubernetes operator for managing Materialize instances
module "operator" {
  source = "../../modules/operator"

  name_prefix                    = var.name_prefix
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
  instance_name        = local.materialize_instance_name
  instance_namespace   = local.materialize_instance_namespace
  metadata_backend_url = local.metadata_backend_url
  persist_backend_url  = local.persist_backend_url

  # The password for the external login to the Materialize instance
  external_login_password_mz_system = random_password.external_login_password_mz_system.result

  # GCP workload identity annotation for service account
  # TODO: this needs a fix in Environmentd Client. KSA based access to storage doesn't work end to end
  service_account_annotations = {
    "iam.gke.io/gcp-service-account" = module.gke.workload_identity_sa_email
  }


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

  instance_name = local.materialize_instance_name
  namespace     = local.materialize_instance_namespace
  resource_id   = module.materialize_instance[0].instance_resource_id

  depends_on = [
    module.materialize_instance,
  ]
}
