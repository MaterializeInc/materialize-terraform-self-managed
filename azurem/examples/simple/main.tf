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

module "networking" {
  source = "../../modules/networking"

  resource_group_name  = var.resource_group_name
  location             = var.location
  prefix               = var.prefix
  vnet_address_space   = var.vnet_config.address_space
  subnet_cidr          = var.vnet_config.subnet_cidr
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
  default_node_pool_node_count  = 1
  default_node_pool_system_only = true

  # Optional: Enable monitoring
  enable_azure_monitor       = var.aks_config.enable_azure_monitor
  log_analytics_workspace_id = var.aks_config.log_analytics_workspace_id

  tags = var.tags
}

# Separate workload node pool for Materialize
module "materialize_nodepool" {
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
  enable_disk_setup = var.enable_disk_setup

  tags = var.tags
}
