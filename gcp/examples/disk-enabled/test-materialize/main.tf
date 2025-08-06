# Test example for Materialize deployment (disk-enabled cluster)
# This follows the same pattern as the simple example with two-phase deployment

locals {
  common_labels = merge(var.labels, {
    managed_by = "terraform"
    module     = "materialize-test"
  })

  metadata_backend_url = format(
    "postgres://%s:%s@%s:5432/%s?sslmode=disable",
    var.user.name,
    urlencode(var.user.password),
    var.database_host,
    var.database_name
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

provider "google" {
  project = var.project_id
  region  = var.region
}

# Configure Kubernetes provider
provider "kubernetes" {
  host                   = "https://${var.cluster_endpoint}"
  cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gke-gcloud-auth-plugin"
  }
}

# Configure Helm provider
provider "helm" {
  kubernetes {
    host                   = "https://${var.cluster_endpoint}"
    cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "gke-gcloud-auth-plugin"
    }
  }
}

# Create Google Cloud Storage bucket for Materialize persistent data storage
module "storage" {
  source = "../../../modules/storage"

  project_id      = var.project_id
  region          = var.region
  prefix          = var.prefix
  service_account = var.workload_identity_sa_email
  versioning      = var.storage_bucket_versioning
  version_ttl     = var.storage_bucket_version_ttl

  labels = local.common_labels
}

# Install cert-manager for SSL certificate management
module "certificates" {
  source = "../../../../kubernetes/modules/certificates"

  install_cert_manager           = var.install_cert_manager
  cert_manager_install_timeout   = var.cert_manager_install_timeout
  cert_manager_chart_version     = var.cert_manager_chart_version
  use_self_signed_cluster_issuer = var.install_materialize_instance
  cert_manager_namespace         = var.cert_manager_namespace
  name_prefix                    = var.prefix
}

# Install OpenEBS for disk-based storage
module "openebs" {
  source = "../../../../kubernetes/modules/openebs"

  openebs_namespace        = var.openebs_namespace
  openebs_version          = var.openebs_chart_version
  install_openebs          = var.install_openebs
  create_openebs_namespace = true
}

# Install Materialize Kubernetes operator
module "operator" {
  count  = var.install_materialize_operator ? 1 : 0
  source = "../../../modules/operator"

  name_prefix                    = var.prefix
  use_self_signed_cluster_issuer = var.install_materialize_instance
  enable_disk_support            = var.disk_setup_enabled
  region                         = var.region
  operator_namespace             = var.operator_namespace

  depends_on = [
    module.storage,
    module.certificates,
    module.openebs,
  ]
}

# Deploy Materialize instance
module "materialize_instance" {
  count = var.install_materialize_instance ? 1 : 0

  source               = "../../../../kubernetes/modules/materialize-instance"
  instance_name        = var.instance_name
  instance_namespace   = var.instance_namespace
  metadata_backend_url = local.metadata_backend_url
  persist_backend_url  = local.persist_backend_url

  # The password for the external login to the Materialize instance
  external_login_password_mz_system = var.external_login_password

  depends_on = [
    module.certificates,
    module.operator,
    module.openebs,
  ]
}

# Configure load balancers for external access
module "load_balancers" {
  count = var.install_materialize_instance ? 1 : 0

  source = "../../../modules/load_balancers"

  instance_name = var.instance_name
  namespace     = var.instance_namespace
  resource_id   = module.materialize_instance[0].instance_resource_id

  depends_on = [
    module.materialize_instance,
  ]
}