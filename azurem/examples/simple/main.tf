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
    min_nodes            = 2
    max_nodes            = 5
    node_count           = null
    disk_size_gb         = 100
    swap_enabled         = true
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

  storage_container_name = "materialize"

  metadata_backend_url = format(
    "postgres://%s:%s@%s/%s?sslmode=require",
    module.database.administrator_login,
    urlencode(module.database.administrator_password),
    module.database.server_fqdn,
    local.database_config.database_name
  )

  persist_backend_url = format(
    "%s%s",
    module.storage.primary_blob_endpoint,
    module.storage.container_name,
  )

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
      effect = "NoSchedule"
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
}


resource "azurerm_resource_group" "materialize" {
  name     = var.resource_group_name
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

  tags = var.tags

  depends_on = [azurerm_resource_group.materialize]
}

# AKS Cluster with Default Node Pool
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

  # Default node pool with autoscaling (runs all workloads except Materialize)
  default_node_pool_vm_size             = "Standard_D4pds_v6"
  default_node_pool_enable_auto_scaling = true
  default_node_pool_min_count           = 2
  default_node_pool_max_count           = 5
  default_node_pool_node_labels         = local.generic_node_labels

  # Optional: Enable monitoring
  enable_azure_monitor       = local.aks_config.enable_azure_monitor
  log_analytics_workspace_id = local.aks_config.log_analytics_workspace_id

  tags = var.tags

  depends_on = [azurerm_resource_group.materialize]
}

# Materialize-dedicated node pool with taints (via labels on Azure)
module "materialize_nodepool" {
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

  vm_size      = local.node_pool_config.vm_size
  disk_size_gb = local.node_pool_config.disk_size_gb
  swap_enabled = local.node_pool_config.swap_enabled

  labels = local.materialize_node_labels

  # Materialize-specific taint to isolate workloads
  # https://github.com/Azure/AKS/issues/2934
  # Note: Once applied, these cannot be manually removed due to AKS webhook restrictions
  node_taints = local.materialize_node_taints

  tags = var.tags

  depends_on = [azurerm_resource_group.materialize]
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

  tags = var.tags
}

module "storage" {
  source = "../../modules/storage"

  resource_group_name            = azurerm_resource_group.materialize.name
  location                       = var.location
  prefix                         = var.name_prefix
  workload_identity_principal_id = module.aks.workload_identity_principal_id
  subnets                        = [module.networking.aks_subnet_id]
  container_name                 = local.storage_container_name

  # Workload identity federation configuration
  workload_identity_id      = module.aks.workload_identity_id
  oidc_issuer_url           = module.aks.cluster_oidc_issuer_url
  service_account_namespace = local.materialize_instance_namespace
  service_account_name      = local.materialize_instance_name

  storage_account_tags = var.tags

  depends_on = [azurerm_resource_group.materialize]
}

resource "random_password" "external_login_password_mz_system" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

module "cert_manager" {
  source = "../../../kubernetes/modules/cert-manager"

  node_selector = local.generic_node_labels

  depends_on = [
    module.aks,
  ]
}

module "self_signed_cluster_issuer" {
  count = var.install_materialize_instance ? 1 : 0

  source = "../../../kubernetes/modules/self-signed-cluster-issuer"

  name_prefix = var.name_prefix

  depends_on = [
    module.cert_manager,
  ]
}

module "operator" {
  source = "../../modules/operator"

  name_prefix = var.name_prefix
  location    = var.location

  instance_pod_tolerations = local.materialize_tolerations
  instance_node_selector   = local.materialize_node_labels

  # node selector for operator and metrics-server workloads
  operator_node_selector = local.generic_node_labels

  depends_on = [
    module.aks,
    module.database,
    module.storage,
  ]
}

module "materialize_instance" {
  count = var.install_materialize_instance ? 1 : 0

  source               = "../../../kubernetes/modules/materialize-instance"
  instance_name        = local.materialize_instance_name
  instance_namespace   = local.materialize_instance_namespace
  metadata_backend_url = local.metadata_backend_url
  persist_backend_url  = local.persist_backend_url

  # The password for the external login to the Materialize instance
  external_login_password_mz_system = random_password.external_login_password_mz_system.result

  # Azure workload identity annotations for service account
  service_account_annotations = {
    "azure.workload.identity/client-id" = module.aks.workload_identity_client_id
  }
  pod_labels = {
    "azure.workload.identity/use" = "true"
  }

  license_key = var.license_key

  issuer_ref = {
    name = module.self_signed_cluster_issuer[0].issuer_name
    kind = "ClusterIssuer"
  }

  depends_on = [
    module.aks,
    module.database,
    module.storage,
    module.networking,
    module.self_signed_cluster_issuer,
    module.operator,
    module.materialize_nodepool,
  ]
}

module "load_balancers" {
  count = var.install_materialize_instance ? 1 : 0

  source = "../../modules/load_balancers"

  instance_name = local.materialize_instance_name
  namespace     = local.materialize_instance_namespace
  resource_id   = module.materialize_instance[0].instance_resource_id
  internal      = true

  depends_on = [
    module.materialize_instance,
  ]
}
