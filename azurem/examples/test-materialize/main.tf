provider "azurerm" {
  subscription_id = var.subscription_id

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = false
    }
  }
}

provider "kubernetes" {
  host                   = var.cluster_endpoint
  client_certificate     = base64decode(var.kube_config.client_certificate)
  client_key             = base64decode(var.kube_config.client_key)
  cluster_ca_certificate = base64decode(var.kube_config.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = var.cluster_endpoint
    client_certificate     = base64decode(var.kube_config.client_certificate)
    client_key             = base64decode(var.kube_config.client_key)
    cluster_ca_certificate = base64decode(var.kube_config.cluster_ca_certificate)
  }
}

locals {
  metadata_backend_url = format(
    "postgres://%s@%s/%s?sslmode=require",
    "${var.database_admin_user.name}:${var.database_admin_user.password}",
    var.database_host,
    var.database_name
  )

  persist_backend_url = format(
    "%s%s?%s",
    module.storage.primary_blob_endpoint,
    module.storage.container_name,
    module.storage.primary_blob_sas_token
  )
}

resource "random_password" "external_login_password_mz_system" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

module "storage" {
  source = "../../modules/storage"

  resource_group_name   = var.resource_group_name
  location              = var.location
  prefix                = var.prefix
  identity_principal_id = var.cluster_identity_principal_id
  subnets               = var.subnets
  container_name        = var.storage_config.container_name
  container_access_type = var.storage_config.container_access_type

  tags = var.tags
}

module "openebs" {
  source = "../../../kubernetes/modules/openebs"

  install_openebs          = var.enable_disk_support
  create_openebs_namespace = true
  openebs_namespace        = var.openebs_namespace
  openebs_version          = var.openebs_version
}

module "certificates" {
  source = "../../../kubernetes/modules/certificates"

  install_cert_manager           = var.install_cert_manager
  cert_manager_install_timeout   = var.cert_manager_install_timeout
  cert_manager_chart_version     = var.cert_manager_chart_version
  use_self_signed_cluster_issuer = var.install_materialize_instance
  cert_manager_namespace         = var.cert_manager_namespace
  name_prefix                    = var.prefix
}

module "operator" {
  source = "../../modules/operator"

  name_prefix                    = var.prefix
  use_self_signed_cluster_issuer = var.install_materialize_instance
  location                       = var.location
  enable_disk_support            = var.enable_disk_support
  operator_namespace             = var.operator_namespace

  depends_on = [
    module.certificates,
  ]
}

module "materialize_instance" {
  count = var.install_materialize_instance ? 1 : 0

  source               = "../../../kubernetes/modules/materialize-instance"
  instance_name        = var.instance_name
  instance_namespace   = var.instance_namespace
  metadata_backend_url = local.metadata_backend_url
  persist_backend_url  = local.persist_backend_url

  # The password for the external login to the Materialize instance
  external_login_password_mz_system = random_password.external_login_password_mz_system.result

  depends_on = [
    module.certificates,
    module.operator,
    module.openebs,
    module.storage,
  ]
}

module "load_balancers" {
  count = var.install_materialize_instance ? 1 : 0

  source = "../../modules/load_balancers"

  instance_name = var.instance_name
  namespace     = var.instance_namespace
  resource_id   = module.materialize_instance[0].instance_resource_id
  internal      = true

  depends_on = [
    module.materialize_instance,
  ]
}

