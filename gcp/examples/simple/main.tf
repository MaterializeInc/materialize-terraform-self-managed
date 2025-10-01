provider "google" {
  project        = var.project_id
  region         = var.region
  default_labels = var.labels
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

  materialize_operator_namespace = "materialize"
  materialize_instance_namespace = "materialize-environment"
  materialize_instance_name      = "main"

  # Common node scheduling configuration
  generic_node_labels = {
    "workload" = "generic"
  }

  materialize_node_labels = {
    "workload" = "materialize-instance"
  }

  materialize_node_taints = [
    {
      key    = "materialize.cloud/workload"
      value  = "materialize-instance"
      effect = "NO_SCHEDULE"
    }
  ]

  materialize_tolerations = [
    {
      key      = "materialize.cloud/workload"
      value    = "materialize-instance"
      operator = "Equal"
      effect   = "NoSchedule"
    }
  ]


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
    machine_type = "n2-highmem-8"
    disk_size_gb = 100
    min_nodes    = 2
    max_nodes    = 5
  }

  database_config = {
    tier      = "db-custom-2-4096"
    database  = { name = "materialize", charset = "UTF8", collation = "en_US.UTF8" }
    user_name = "materialize"
  }

  local_ssd_count = 1
  swap_enabled    = true

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
  labels     = var.labels
}

# Set up Google Kubernetes Engine (GKE) cluster
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
  labels      = var.labels
}

# Create and configure generic node pool for all workloads except Materialize
module "generic_nodepool" {
  source     = "../../modules/nodepool"
  depends_on = [module.gke]

  prefix                = "${var.name_prefix}-generic"
  region                = var.region
  enable_private_nodes  = true
  cluster_name          = module.gke.cluster_name
  project_id            = var.project_id
  min_nodes             = 2
  max_nodes             = 5
  machine_type          = "e2-standard-8"
  disk_size_gb          = 50
  service_account_email = module.gke.service_account_email
  labels                = local.generic_node_labels
  swap_enabled          = false
  local_ssd_count       = 0
}

# Create and configure Materialize-dedicated node pool with taints
module "materialize_nodepool" {
  source     = "../../modules/nodepool"
  depends_on = [module.gke]

  prefix                = "${var.name_prefix}-mz"
  region                = var.region
  enable_private_nodes  = true
  cluster_name          = module.gke.cluster_name
  project_id            = var.project_id
  min_nodes             = local.gke_config.min_nodes
  max_nodes             = local.gke_config.max_nodes
  machine_type          = local.gke_config.machine_type
  disk_size_gb          = local.gke_config.disk_size_gb
  service_account_email = module.gke.service_account_email
  labels                = merge(var.labels, local.materialize_node_labels)
  # Materialize-specific taint to isolate workloads
  node_taints = local.materialize_node_taints

  swap_enabled    = local.swap_enabled
  local_ssd_count = local.local_ssd_count
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

  labels = var.labels
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

  labels = var.labels
}

# Install cert-manager for SSL certificate management and create cluster issuer
module "certificates" {
  source = "../../../kubernetes/modules/certificates"

  install_cert_manager           = true
  use_self_signed_cluster_issuer = var.install_materialize_instance
  cert_manager_namespace         = "cert-manager"
  name_prefix                    = var.name_prefix
  node_selector                  = local.generic_node_labels



  depends_on = [
    module.gke,
    module.generic_nodepool,
  ]
}

# Install Materialize Kubernetes operator for managing Materialize instances
module "operator" {
  source = "../../modules/operator"

  name_prefix                    = var.name_prefix
  use_self_signed_cluster_issuer = var.install_materialize_instance
  region                         = var.region

  # ARM tolerations and node selector for all operator workloads on GCP
  instance_pod_tolerations = local.materialize_tolerations
  instance_node_selector   = local.materialize_node_labels

  # node selector for operator and metrics-server workloads
  operator_node_selector = local.generic_node_labels


  helm_values = {
    observability = {
      podMetrics = {
        enabled = false
      }
      prometheus = {
        scrapeAnnotations = {
          enable = false
        }
      }
    }
  }

  depends_on = [
    module.gke,
    module.generic_nodepool,
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

  license_key = var.license_key

  depends_on = [
    module.gke,
    module.database,
    module.storage,
    module.networking,
    module.certificates,
    module.operator,
    module.materialize_nodepool,
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
