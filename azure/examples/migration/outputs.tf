# =============================================================================
# Migration Reference Outputs
# =============================================================================

# Networking
output "networking" {
  description = "Networking details"
  value = {
    vnet_id       = azurerm_virtual_network.vnet.id
    vnet_name     = azurerm_virtual_network.vnet.name
    aks_subnet_id = azurerm_subnet.aks.id
    pg_subnet_id  = azurerm_subnet.postgres.id
    dns_zone_id   = azurerm_private_dns_zone.postgres.id
  }
}

# AKS Cluster
output "aks_cluster" {
  description = "AKS cluster details"
  value = {
    name     = azurerm_kubernetes_cluster.aks.name
    endpoint = azurerm_kubernetes_cluster.aks.kube_config[0].host
    location = azurerm_kubernetes_cluster.aks.location
  }
  sensitive = true
}

output "kube_config_raw" {
  description = "The raw kube_config for the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive   = true
}

# Database
output "database" {
  description = "Azure Database for PostgreSQL details"
  value = {
    server_name = azurerm_postgresql_flexible_server.postgres.name
    fqdn        = azurerm_postgresql_flexible_server.postgres.fqdn
  }
}

# Storage
output "storage" {
  description = "Azure Storage Account details"
  value = {
    name           = module.storage.storage_account_name
    blob_endpoint  = module.storage.primary_blob_endpoint
    container_name = module.storage.container_name
  }
}

# Operator
output "operator" {
  description = "Materialize operator details"
  value = {
    namespace = module.operator.operator_namespace
  }
}

# Materialize Instance
output "materialize_instance_name" {
  description = "Materialize instance name"
  value       = local.materialize_instance_name
}

output "materialize_instance_namespace" {
  description = "Materialize instance namespace"
  value       = local.materialize_instance_namespace
}

output "materialize_instance_resource_id" {
  description = "Materialize instance resource ID"
  value       = module.materialize_instance.instance_resource_id
}

output "materialize_instance_metadata_backend_url" {
  description = "Materialize instance metadata backend URL"
  value       = local.metadata_backend_url
  sensitive   = true
}

output "materialize_instance_persist_backend_url" {
  description = "Materialize instance persist backend URL"
  value       = local.persist_backend_url
  sensitive   = true
}

# Load Balancer
output "load_balancer_details" {
  description = "Details of the Materialize instance load balancers"
  value = {
    console_ip   = module.load_balancers.console_load_balancer_ip
    balancerd_ip = module.load_balancers.balancerd_load_balancer_ip
  }
}

output "external_login_password_mz_system" {
  description = "Password for external login to Materialize"
  value       = var.external_login_password_mz_system
  sensitive   = true
}
