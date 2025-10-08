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

# AKS cluster with default node pool for all workloads
module "aks" {
  source = "../../../../azurem/modules/aks"

  resource_group_name = var.resource_group_name
  kubernetes_version  = var.kubernetes_version
  service_cidr        = var.service_cidr
  location            = var.location
  prefix              = var.prefix
  vnet_name           = var.vnet_name
  subnet_name         = var.subnet_name
  subnet_id           = var.subnet_id

  # Default node pool configuration
  default_node_pool_vm_size             = var.default_node_pool_vm_size
  default_node_pool_enable_auto_scaling = var.default_node_pool_enable_auto_scaling
  default_node_pool_node_count          = var.default_node_pool_node_count
  default_node_pool_min_count           = var.default_node_pool_min_count
  default_node_pool_max_count           = var.default_node_pool_max_count
  default_node_pool_node_labels         = var.node_labels

  enable_azure_monitor       = var.enable_azure_monitor
  log_analytics_workspace_id = var.log_analytics_workspace_id

  tags = var.tags
}

# Additional node pool for Materialize workloads
module "nodepool" {
  source = "../../../../azurem/modules/nodepool"

  prefix     = var.prefix
  cluster_id = module.aks.cluster_id
  subnet_id  = var.subnet_id

  vm_size      = var.nodepool_vm_size
  disk_size_gb = var.disk_size_gb

  autoscaling_config = {
    enabled    = var.auto_scaling_enabled
    min_nodes  = var.min_nodes
    max_nodes  = var.max_nodes
    node_count = var.node_count
  }

  swap_enabled = var.swap_enabled
  labels       = var.node_labels
  tags         = var.tags
}

# Database
module "database" {
  source = "../../../../azurem/modules/database"

  # Database configuration
  databases = var.databases

  # Administrator configuration
  administrator_login    = var.administrator_login
  administrator_password = var.administrator_password

  # Infrastructure configuration
  resource_group_name = var.resource_group_name
  location            = var.location
  prefix              = var.prefix
  subnet_id           = var.database_subnet_id
  private_dns_zone_id = var.private_dns_zone_id

  # Database server configuration
  sku_name                      = var.sku_name
  postgres_version              = var.postgres_version
  storage_mb                    = var.storage_mb
  backup_retention_days         = var.backup_retention_days
  public_network_access_enabled = var.public_network_access_enabled

  tags = var.tags
}

# Kubernetes provider configuration
provider "kubernetes" {
  host                   = module.aks.cluster_endpoint
  client_certificate     = base64decode(module.aks.kube_config[0].client_certificate)
  client_key             = base64decode(module.aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(module.aks.kube_config[0].cluster_ca_certificate)
}

# Helm provider configuration
provider "helm" {
  kubernetes {
    host                   = module.aks.cluster_endpoint
    client_certificate     = base64decode(module.aks.kube_config[0].client_certificate)
    client_key             = base64decode(module.aks.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(module.aks.kube_config[0].cluster_ca_certificate)
  }
}

# Cert Manager
module "cert_manager" {
  source = "../../../../kubernetes/modules/cert-manager"

  install_timeout = var.cert_manager_install_timeout
  chart_version   = var.cert_manager_chart_version
  namespace       = var.cert_manager_namespace

  depends_on = [module.aks]
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
  source = "../../../../azurem/modules/operator"

  name_prefix        = var.prefix
  location           = var.location
  operator_namespace = var.operator_namespace
  swap_enabled       = var.swap_enabled

  depends_on = [module.aks]
}

# Storage (Azure Blob)
module "storage" {
  source = "../../../../azurem/modules/storage"

  prefix                = var.prefix
  resource_group_name   = var.resource_group_name
  location              = var.location
  container_name        = var.container_name
  container_access_type = var.container_access_type

  workload_identity_principal_id = module.aks.workload_identity_principal_id
  workload_identity_id           = module.aks.workload_identity_id
  oidc_issuer_url                = module.aks.cluster_oidc_issuer_url
  service_account_namespace      = var.instance_namespace
  service_account_name           = var.instance_name

  depends_on = [module.aks]
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

  # Azure storage account annotation for service account
  service_account_annotations = {
    "azure.workload.identity/client-id" = module.storage.workload_identity_client_id
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

  source = "../../../../azurem/modules/load_balancers"

  instance_name = var.instance_name
  namespace     = var.instance_namespace
  resource_id   = module.materialize_instance[0].instance_resource_id

  depends_on = [module.materialize_instance]
}

# Local values for backend URLs
locals {
  metadata_backend_url = format(
    "postgres://%s:%s@%s/%s?sslmode=require",
    var.administrator_login,
    urlencode(var.administrator_password),
    module.database.server_fqdn,
    var.database_name
  )

  persist_backend_url = format(
    "%s%s",
    module.storage.primary_blob_endpoint,
    module.storage.container_name,
  )
}
