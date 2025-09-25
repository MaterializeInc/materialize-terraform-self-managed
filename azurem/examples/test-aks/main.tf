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
  host                   = module.aks.cluster_endpoint
  client_certificate     = base64decode(module.aks.kube_config[0].client_certificate)
  client_key             = base64decode(module.aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(module.aks.kube_config[0].cluster_ca_certificate)
}

# AKS cluster with default node pool for all workloads
module "aks" {
  source = "../../modules/aks"

  resource_group_name = var.resource_group_name
  kubernetes_version  = var.kubernetes_version
  service_cidr        = var.service_cidr
  location            = var.location
  prefix              = var.prefix
  vnet_name           = var.vnet_name
  subnet_name         = var.subnet_name
  subnet_id           = var.subnet_id

  # Default node pool with autoscaling (runs all workloads for tests)
  default_node_pool_vm_size             = var.default_node_pool_vm_size
  default_node_pool_enable_auto_scaling = var.default_node_pool_enable_auto_scaling
  default_node_pool_node_count          = var.default_node_pool_node_count
  default_node_pool_min_count           = var.default_node_pool_min_count
  default_node_pool_max_count           = var.default_node_pool_max_count

  # Optional: Enable monitoring
  enable_azure_monitor       = var.enable_azure_monitor
  log_analytics_workspace_id = var.log_analytics_workspace_id

  tags = var.tags
}

# Separate workload node pool for Materialize
module "nodepool" {
  source = "../../modules/nodepool"

  prefix     = var.prefix
  cluster_id = module.aks.cluster_id
  subnet_id  = var.subnet_id

  # Workload-specific configuration
  autoscaling_config = {
    enabled    = var.auto_scaling_enabled
    min_nodes  = var.min_nodes
    max_nodes  = var.max_nodes
    node_count = var.node_count
  }
  vm_size      = var.nodepool_vm_size
  disk_size_gb = var.disk_size_gb
  swap_enabled = var.swap_enabled

  tags = var.tags
}

