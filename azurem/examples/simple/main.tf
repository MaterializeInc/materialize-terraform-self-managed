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
  resource_group_name = "materialize"

  vnet_config = {
    address_space        = "20.0.0.0/16"
    aks_subnet_cidr      = "20.0.0.0/20"
    postgres_subnet_cidr = "20.0.16.0/24"
  }

  aks_config = {
    kubernetes_version         = "1.32"
    service_cidr               = "20.1.0.0/16"
    enable_azure_monitor       = false
    log_analytics_workspace_id = null
  }

  node_pool_config = {
    vm_size              = "Standard_E4pds_v6"
    auto_scaling_enabled = true
    min_nodes            = 1
    max_nodes            = 5
    node_count           = null
    disk_size_gb         = 100
  }

  database_config = {
    sku_name                      = "GP_Standard_D2s_v3"
    postgres_version              = "15"
    storage_mb                    = 32768
    backup_retention_days         = 7
    administrator_login           = "materialize"
    administrator_password        = null # Will generate random password
    database_name                 = "materialize"
    public_network_access_enabled = false
  }

  storage_config = {
    # https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blob-block-blob-premium#premium-scenarios
    account_tier             = "Premium"
    account_replication_type = "LRS"
    account_kind             = "BlockBlobStorage"
    container_name           = "materialize"
    container_access_type    = "private"
  }

  tags = {
    Environment = "development"
    Project     = "materialize"
  }

  # Disk support configuration
  disk_config = {
    enable_disk_support = true
    openebs_namespace   = "openebs"
  }


  metadata_backend_url = format(
    "postgres://%s@%s/%s?sslmode=require",
    "${module.database.administrator_login}:${module.database.administrator_password}",
    module.database.server_fqdn,
    local.database_config.database_name
  )

  persist_backend_url = format(
    "%s%s?%s",
    module.storage.primary_blob_endpoint,
    module.storage.container_name,
    module.storage.primary_blob_sas_token
  )
}


resource "azurerm_resource_group" "materialize" {
  name     = local.resource_group_name
  location = var.location
}


module "networking" {
  source = "../../modules/networking"

  resource_group_name  = azurerm_resource_group.materialize.name
  location             = var.location
  prefix               = var.name_prefix
  vnet_address_space   = local.vnet_config.address_space
  aks_subnet_cidr      = local.vnet_config.aks_subnet_cidr
  postgres_subnet_cidr = local.vnet_config.postgres_subnet_cidr
}

# Pattern A: Minimal system-only default node pool + separate workload node pools
module "aks" {
  source = "../../modules/aks"

  resource_group_name = azurerm_resource_group.materialize.name
  kubernetes_version  = local.aks_config.kubernetes_version
  service_cidr        = local.aks_config.service_cidr
  location            = var.location
  prefix              = var.name_prefix
  vnet_name           = module.networking.vnet_name
  subnet_name         = module.networking.aks_subnet_name
  subnet_id           = module.networking.aks_subnet_id

  # System-only node pool (minimal)
  default_node_pool_vm_size     = "Standard_D2s_v3"
  default_node_pool_node_count  = 2
  default_node_pool_system_only = true

  # Optional: Enable monitoring
  enable_azure_monitor       = local.aks_config.enable_azure_monitor
  log_analytics_workspace_id = local.aks_config.log_analytics_workspace_id

  tags = local.tags
}

# Separate workload node pool for Materialize
module "nodepool" {
  source = "../../modules/nodepool"

  prefix     = var.name_prefix
  cluster_id = module.aks.cluster_id
  subnet_id  = module.networking.aks_subnet_id

  # Workload-specific configuration
  autoscaling_config = {
    enabled    = local.node_pool_config.auto_scaling_enabled
    min_nodes  = local.node_pool_config.min_nodes
    max_nodes  = local.node_pool_config.max_nodes
    node_count = local.node_pool_config.node_count
  }
  vm_size           = local.node_pool_config.vm_size
  disk_size_gb      = local.node_pool_config.disk_size_gb
  enable_disk_setup = local.disk_config.enable_disk_support

  tags = local.tags
}


module "database" {
  source = "../../modules/database"

  depends_on = [module.networking]

  # Database configuration using new structure
  databases = [
    {
      name      = local.database_config.database_name
      charset   = "UTF8"
      collation = "en_US.utf8"
    }
  ]

  # Administrator configuration
  administrator_login = local.database_config.administrator_login
  # No administrator password is provided, so a random one will be generated

  # Infrastructure configuration
  resource_group_name = azurerm_resource_group.materialize.name
  location            = var.location
  prefix              = var.name_prefix
  subnet_id           = module.networking.postgres_subnet_id
  private_dns_zone_id = module.networking.private_dns_zone_id

  # Database server configuration
  sku_name                      = local.database_config.sku_name
  postgres_version              = local.database_config.postgres_version
  storage_mb                    = local.database_config.storage_mb
  backup_retention_days         = local.database_config.backup_retention_days
  public_network_access_enabled = local.database_config.public_network_access_enabled

  tags = local.tags
}

module "storage" {
  source = "../../modules/storage"

  resource_group_name      = azurerm_resource_group.materialize.name
  location                 = var.location
  prefix                   = var.name_prefix
  identity_principal_id    = module.aks.cluster_identity_principal_id
  subnets                  = [module.networking.aks_subnet_id]
  account_tier             = local.storage_config.account_tier
  account_replication_type = local.storage_config.account_replication_type
  account_kind             = local.storage_config.account_kind
  container_name           = local.storage_config.container_name
  container_access_type    = local.storage_config.container_access_type

  tags = local.tags
}

module "openebs" {
  source = "../../../kubernetes/modules/openebs"
  depends_on = [
    module.aks,
    module.nodepool
  ]

  install_openebs          = local.disk_config.enable_disk_support
  create_openebs_namespace = true
  openebs_namespace        = local.disk_config.openebs_namespace
}

resource "random_password" "external_login_password_mz_system" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

module "certificates" {
  source = "../../../kubernetes/modules/certificates"

  install_cert_manager           = true
  use_self_signed_cluster_issuer = var.install_materialize_instance
  cert_manager_namespace         = "cert-manager"
  name_prefix                    = var.name_prefix

  depends_on = [
    module.aks,
    module.nodepool,
  ]
}

module "operator" {
  source = "../../modules/operator"

  name_prefix                    = var.name_prefix
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
