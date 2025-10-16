# =============================================================================
# AKS CLUSTER OUTPUTS
# =============================================================================

output "cluster_name" {
  description = "The name of the AKS cluster"
  value       = module.aks.cluster_name
}

output "cluster_id" {
  description = "The ID of the AKS cluster"
  value       = module.aks.cluster_id
}

output "cluster_fqdn" {
  description = "The FQDN of the AKS cluster"
  value       = module.aks.cluster_fqdn
}

output "cluster_endpoint" {
  description = "The endpoint of the AKS cluster"
  value       = module.aks.cluster_endpoint
  sensitive   = true
}

output "kube_config" {
  description = "The kube config of the AKS cluster"
  value       = module.aks.kube_config
  sensitive   = true
}

output "workload_identity_principal_id" {
  description = "The principal ID of the workload identity"
  value       = module.aks.workload_identity_principal_id
}

output "workload_identity_client_id" {
  description = "The client ID of the workload identity"
  value       = module.aks.workload_identity_client_id
}

output "workload_identity_id" {
  description = "The ID of the workload identity"
  value       = module.aks.workload_identity_id
}

output "cluster_identity_principal_id" {
  description = "The principal ID of the cluster identity"
  value       = module.aks.cluster_identity_principal_id
}

output "cluster_identity_client_id" {
  description = "The client ID of the cluster identity"
  value       = module.aks.cluster_identity_client_id
}

output "cluster_identity_id" {
  description = "The ID of the cluster identity"
  value       = module.aks.cluster_identity_id
}

output "cluster_oidc_issuer_url" {
  description = "The OIDC issuer URL of the AKS cluster"
  value       = module.aks.cluster_oidc_issuer_url
}

output "nodepool_name" {
  description = "The name of the Materialize node pool"
  value       = module.nodepool.nodepool_name
}

# =============================================================================
# DATABASE OUTPUTS
# =============================================================================

output "server_name" {
  description = "The name of the PostgreSQL server"
  value       = module.database.server_name
}

output "server_fqdn" {
  description = "The FQDN of the PostgreSQL server"
  value       = module.database.server_fqdn
}

output "administrator_login" {
  description = "The administrator login for the PostgreSQL server"
  value       = module.database.administrator_login
}

output "administrator_password" {
  description = "The administrator password for the PostgreSQL server"
  value       = module.database.administrator_password
  sensitive   = true
}

output "databases" {
  description = "The databases"
  value       = module.database.databases
}

output "database_names" {
  description = "The names of the databases"
  value       = module.database.database_names
}

# =============================================================================
# AZURE BLOB STORAGE OUTPUTS
# =============================================================================

output "storage_account_name" {
  description = "The name of the storage account"
  value       = module.storage.storage_account_name
}

output "storage_primary_blob_endpoint" {
  description = "The primary blob endpoint of the storage account"
  value       = module.storage.primary_blob_endpoint
}

output "storage_container_name" {
  description = "The name of the storage container"
  value       = module.storage.container_name
}

output "storage_workload_identity_client_id" {
  description = "The client ID of the workload identity for storage"
  value       = module.aks.workload_identity_client_id
}

# =============================================================================
# MATERIALIZE BACKEND URLS
# =============================================================================

output "metadata_backend_url" {
  description = "Azure blob storage URL for metadata in the format required by Materialize"
  value       = local.metadata_backend_url
  sensitive   = true
}

output "persist_backend_url" {
  description = "Azure blob storage URL for persist in the format required by Materialize"
  value       = local.persist_backend_url
  sensitive   = true
}

# =============================================================================
# MATERIALIZE OPERATOR OUTPUTS
# =============================================================================

output "operator_namespace" {
  description = "Materialize operator namespace"
  value       = var.operator_namespace
}

# =============================================================================
# MATERIALIZE INSTANCE OUTPUTS
# =============================================================================

output "instance_resource_id" {
  description = "The resource ID of the Materialize instance"
  value       = module.materialize_instance.instance_resource_id
}

output "external_login_password" {
  description = "The external login password for the Materialize instance"
  value       = var.external_login_password_mz_system
  sensitive   = true
}

# =============================================================================
# LOAD BALANCER OUTPUTS
# =============================================================================

output "console_load_balancer_ip" {
  description = "IP address of load balancer pointing at the web console"
  value       = module.load_balancer.console_load_balancer_ip
}

output "balancerd_load_balancer_ip" {
  description = "IP address of load balancer pointing at balancerd"
  value       = module.load_balancer.balancerd_load_balancer_ip
}

# =============================================================================
# CERTIFICATE OUTPUTS
# =============================================================================

output "cluster_issuer_name" {
  description = "Name of the cluster issuer"
  value       = module.self_signed_cluster_issuer.issuer_name
}
