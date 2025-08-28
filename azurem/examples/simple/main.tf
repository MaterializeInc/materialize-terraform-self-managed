provider "azurerm" {
  # Set the Azure subscription ID here or use the ARM_SUBSCRIPTION_ID environment variable
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
  host                   = module.aks.cluster_endpoint
  client_certificate     = base64decode(module.aks.kube_config[0].client_certificate)
  client_key             = base64decode(module.aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(module.aks.kube_config[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = module.aks.cluster_endpoint
    client_certificate     = base64decode(module.aks.kube_config[0].client_certificate)
    client_key             = base64decode(module.aks.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(module.aks.kube_config[0].cluster_ca_certificate)
  }
}



locals {
  # Disk support configuration
  disk_config = {
    install_openebs   = var.enable_disk_support ? lookup(var.disk_support_config, "install_openebs", true) : false
    local_ssd_count   = lookup(var.disk_support_config, "local_ssd_count", 1)
    openebs_version   = lookup(var.disk_support_config, "openebs_version", "4.2.0")
    openebs_namespace = lookup(var.disk_support_config, "openebs_namespace", "openebs")
  }


  metadata_backend_url = format(
    "postgres://%s@%s/%s?sslmode=require",
    "${module.database.administrator_login}:${module.database.administrator_password}",
    module.database.server_fqdn,
    var.database_config.database_name
  )

  persist_backend_url = format(
    "%s%s?%s",
    module.storage.primary_blob_endpoint,
    module.storage.container_name,
    module.storage.primary_blob_sas_token
  )
}


resource "azurerm_resource_group" "materialize" {
  name     = var.resource_group_name
  location = var.location
}


module "networking" {
  source = "../../modules/networking"

  resource_group_name  = azurerm_resource_group.materialize.name
  location             = var.location
  prefix               = var.prefix
  vnet_address_space   = var.vnet_config.address_space
  aks_subnet_cidr      = var.vnet_config.aks_subnet_cidr
  postgres_subnet_cidr = var.vnet_config.postgres_subnet_cidr
}

# Pattern A: Minimal system-only default node pool + separate workload node pools
module "aks" {
  source = "../../modules/aks"

  resource_group_name = var.resource_group_name
  kubernetes_version  = var.aks_config.kubernetes_version
  service_cidr        = var.aks_config.service_cidr
  location            = var.location
  prefix              = var.prefix
  vnet_name           = module.networking.vnet_name
  subnet_name         = module.networking.aks_subnet_name
  subnet_id           = module.networking.aks_subnet_id

  # System-only node pool (minimal)
  default_node_pool_vm_size     = "Standard_D2s_v3"
  default_node_pool_node_count  = 2
  default_node_pool_system_only = true

  # Optional: Enable monitoring
  enable_azure_monitor       = var.aks_config.enable_azure_monitor
  log_analytics_workspace_id = var.aks_config.log_analytics_workspace_id

  tags = var.tags
}

# Separate workload node pool for Materialize
module "nodepool" {
  source = "../../modules/nodepool"

  prefix     = var.prefix
  cluster_id = module.aks.cluster_id
  subnet_id  = module.networking.aks_subnet_id

  # Workload-specific configuration
  autoscaling_config = {
    enabled    = var.node_pool_config.auto_scaling_enabled
    min_nodes  = var.node_pool_config.min_nodes
    max_nodes  = var.node_pool_config.max_nodes
    node_count = var.node_pool_config.node_count
  }
  vm_size           = var.node_pool_config.vm_size
  disk_size_gb      = var.node_pool_config.disk_size_gb
  enable_disk_setup = var.enable_disk_support
  disk_setup_image  = var.disk_setup_image

  tags = var.tags
}


module "database" {
  source = "../../modules/database"

  depends_on = [module.networking]

  # Database configuration using new structure
  databases = [
    {
      name      = var.database_config.database_name
      charset   = "UTF8"
      collation = "en_US.utf8"
    }
  ]

  # Administrator configuration
  administrator_login = var.database_config.administrator_login
  # No administrator password is provided, so a random one will be generated

  # Infrastructure configuration
  resource_group_name = azurerm_resource_group.materialize.name
  location            = var.location
  prefix              = var.prefix
  subnet_id           = module.networking.postgres_subnet_id
  private_dns_zone_id = module.networking.private_dns_zone_id

  # Database server configuration
  sku_name                      = var.database_config.sku_name
  postgres_version              = var.database_config.postgres_version
  storage_mb                    = var.database_config.storage_mb
  backup_retention_days         = var.database_config.backup_retention_days
  public_network_access_enabled = var.database_config.public_network_access_enabled

  tags = var.tags
}

module "storage" {
  source = "../../modules/storage"

  resource_group_name      = azurerm_resource_group.materialize.name
  location                 = var.location
  prefix                   = var.prefix
  identity_principal_id    = module.aks.cluster_identity_principal_id
  subnets                  = [module.networking.aks_subnet_id]
  account_tier             = var.storage_config.account_tier
  account_replication_type = var.storage_config.account_replication_type
  account_kind             = var.storage_config.account_kind
  container_name           = var.storage_config.container_name
  container_access_type    = var.storage_config.container_access_type

  tags = var.tags
}

module "openebs" {
  source = "../../../kubernetes/modules/openebs"
  depends_on = [
    module.aks,
    module.nodepool
  ]

  install_openebs          = local.disk_config.install_openebs
  create_openebs_namespace = true
  openebs_namespace        = local.disk_config.openebs_namespace
  openebs_version          = local.disk_config.openebs_version
}

resource "random_password" "external_login_password_mz_system" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

module "certificates" {
  source = "../../../kubernetes/modules/certificates"

  install_cert_manager           = var.install_cert_manager
  cert_manager_install_timeout   = var.cert_manager_install_timeout
  cert_manager_chart_version     = var.cert_manager_chart_version
  use_self_signed_cluster_issuer = var.install_materialize_instance
  cert_manager_namespace         = var.cert_manager_namespace
  name_prefix                    = var.prefix

  depends_on = [
    module.aks,
    module.nodepool,
  ]
}

module "operator" {
  count  = var.install_materialize_operator ? 1 : 0
  source = "../../modules/operator"

  name_prefix                    = var.prefix
  use_self_signed_cluster_issuer = var.install_materialize_instance
  location                       = var.location

  depends_on = [
    module.aks,
    module.nodepool,
    module.database,
    module.storage,
    module.certificates,
  ]
}

module "materialize_instance" {
  count = var.install_materialize_instance ? 1 : 0

  source               = "../../../kubernetes/modules/materialize-instance"
  instance_name        = "main"
  instance_namespace   = "materialize-environment"
  metadata_backend_url = local.metadata_backend_url
  persist_backend_url  = local.persist_backend_url

  # The password for the external login to the Materialize instance
  external_login_password_mz_system = random_password.external_login_password_mz_system.result


  depends_on = [
    module.aks,
    module.database,
    module.storage,
    module.networking,
    module.certificates,
    module.operator,
    module.nodepool,
    module.openebs,
  ]
}

module "load_balancers" {
  count = var.install_materialize_instance ? 1 : 0

  source = "../../modules/load_balancers"

  instance_name = "main"
  namespace     = "materialize-environment"
  resource_id   = module.materialize_instance[0].instance_resource_id
  internal      = true

  depends_on = [
    module.materialize_instance,
  ]
}
