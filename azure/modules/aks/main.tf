resource "azurerm_user_assigned_identity" "aks_identity" {
  name                = "${var.prefix}-aks-identity"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

data "azurerm_subscription" "current" {}

resource "azurerm_role_assignment" "aks_network_contributer" {
  scope                = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.Network/virtualNetworks/${var.vnet_name}/subnets/${var.subnet_name}"
  role_definition_name = "Network Contributor"
  principal_id         = resource.azurerm_user_assigned_identity.aks_identity.principal_id
}

# Role assignment for API server subnet (required for VNet Integration)
resource "azurerm_role_assignment" "aks_apiserver_network_contributer" {
  count                = var.enable_api_server_vnet_integration && var.api_server_subnet_id != null ? 1 : 0
  scope                = var.api_server_subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = resource.azurerm_user_assigned_identity.aks_identity.principal_id
}

resource "azurerm_user_assigned_identity" "workload_identity" {
  name                = "${var.prefix}-workload-identity"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.prefix}-aks"
  resource_group_name = var.resource_group_name
  location            = var.location
  dns_prefix          = "${var.prefix}-aks"
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    temporary_name_for_rotation  = "default2"
    name                         = "default"
    vm_size                      = var.default_node_pool_vm_size
    auto_scaling_enabled         = var.default_node_pool_enable_auto_scaling
    node_count                   = var.default_node_pool_enable_auto_scaling ? null : var.default_node_pool_node_count
    min_count                    = var.default_node_pool_enable_auto_scaling ? var.default_node_pool_min_count : null
    max_count                    = var.default_node_pool_enable_auto_scaling ? var.default_node_pool_max_count : null
    only_critical_addons_enabled = false # Default pool runs all workloads except Materialize
    vnet_subnet_id               = var.subnet_id
    os_disk_size_gb              = var.default_node_pool_os_disk_size_gb
    node_labels                  = var.default_node_pool_node_labels

    upgrade_settings {
      max_surge                     = "10%"
      drain_timeout_in_minutes      = 0
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks_identity.id]
  }

  # API Server VNet Integration - Projects API server into a delegated subnet
  # Can be used for BOTH public and private clusters
  # Reference: https://learn.microsoft.com/en-us/azure/aks/api-server-vnet-integration
  api_server_access_profile {
    virtual_network_integration_enabled = var.enable_api_server_vnet_integration
    subnet_id                           = var.api_server_subnet_id
    authorized_ip_ranges                = var.api_server_authorized_ip_ranges
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  dynamic "azure_active_directory_role_based_access_control" {
    for_each = var.enable_azure_ad_rbac ? [1] : []
    content {
      azure_rbac_enabled     = true
      admin_group_object_ids = var.azure_ad_admin_group_object_ids
    }
  }

  dynamic "oms_agent" {
    for_each = var.enable_azure_monitor ? [1] : []
    content {
      log_analytics_workspace_id = var.log_analytics_workspace_id
    }
  }

  network_profile {
    network_plugin     = var.network_plugin
    network_policy     = var.network_policy
    network_data_plane = var.network_data_plane
    service_cidr       = var.service_cidr
    dns_service_ip     = var.dns_service_ip != null ? var.dns_service_ip : cidrhost(var.service_cidr, 10)
    load_balancer_sku  = var.load_balancer_sku
  }

  tags = var.tags

  depends_on = [
    resource.azurerm_role_assignment.aks_network_contributer,
    resource.azurerm_role_assignment.aks_apiserver_network_contributer,
  ]

  lifecycle {
    precondition {
      condition     = !var.enable_azure_monitor || var.log_analytics_workspace_id != null
      error_message = "log_analytics_workspace_id must be provided when enable_azure_monitor is true."
    }

    precondition {
      condition = (
        !var.enable_azure_ad_rbac ||
        length(var.azure_ad_admin_group_object_ids) > 0
      )
      error_message = "azure_ad_admin_group_object_ids must contain at least one group object ID when enable_azure_ad_rbac is true."
    }

    precondition {
      condition = (
        var.network_policy != "cilium" ||
        var.network_data_plane == "cilium"
      )
      error_message = "When network_policy is 'cilium', network_data_plane must also be 'cilium'."
    }

    precondition {
      condition     = !var.enable_api_server_vnet_integration || var.api_server_subnet_id != null
      error_message = "api_server_subnet_id must be provided when enable_api_server_vnet_integration is true."
    }
  }
}
