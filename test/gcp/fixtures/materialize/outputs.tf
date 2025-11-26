# =============================================================================
# GKE CLUSTER OUTPUTS
# =============================================================================

output "cluster_name" {
  description = "GKE cluster name"
  value       = module.gke.cluster_name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = module.gke.cluster_endpoint
}

output "cluster_private_endpoint" {
  description = "GKE cluster private endpoint"
  value       = module.gke.cluster_private_endpoint
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  value       = module.gke.cluster_ca_certificate
  sensitive   = true
}

output "nodepool_name" {
  description = "NodePool name"
  value       = module.nodepool.node_pool_name
}

output "node_service_account" {
  description = "Service account email for nodes"
  value       = module.gke.service_account_email
}

output "workload_identity_sa_email" {
  description = "The email of the Workload Identity service account"
  value       = module.gke.workload_identity_sa_email
}

# =============================================================================
# DATABASE OUTPUTS
# =============================================================================

output "instance_name" {
  description = "The name of the database instance"
  value       = module.database.instance_name
}

output "database_names" {
  description = "List of database names"
  value       = module.database.database_names
}

output "user_names" {
  description = "List of database user names"
  value       = module.database.user_names
}

output "private_ip" {
  description = "The private IP address of the database instance"
  value       = module.database.private_ip
}

output "databases" {
  description = "List of created databases"
  value       = module.database.databases
}

output "users" {
  description = "List of created users with credentials"
  value       = module.database.users
  sensitive   = true
}

# =============================================================================
# GCS STORAGE OUTPUTS
# =============================================================================

output "storage_bucket_name" {
  description = "Name of the storage bucket"
  value       = module.storage.bucket_name
}

output "storage_bucket_url" {
  description = "URL of the storage bucket"
  value       = module.storage.bucket_url
}

output "storage_hmac_access_id" {
  description = "HMAC access ID for storage"
  value       = module.storage.hmac_access_id
  sensitive   = true
}

output "storage_hmac_secret" {
  description = "HMAC secret for storage"
  value       = module.storage.hmac_secret
  sensitive   = true
}

# =============================================================================
# MATERIALIZE BACKEND URLS
# =============================================================================

output "metadata_backend_url" {
  description = "PostgreSQL connection URL in the format required by Materialize"
  value       = local.metadata_backend_url
  sensitive   = true
}

output "persist_backend_url" {
  description = "GCS connection URL in the format required by Materialize"
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
  description = "Materialize instance resource ID"
  value       = module.materialize_instance.instance_resource_id
}

# =============================================================================
# LOAD BALANCER OUTPUTS
# =============================================================================

output "console_load_balancer_ip" {
  description = "Console load balancer IP for external access"
  value       = module.load_balancer.console_load_balancer_ip
}

output "balancerd_load_balancer_ip" {
  description = "Balancerd load balancer IP for external access"
  value       = module.load_balancer.balancerd_load_balancer_ip
}

# =============================================================================
# CERTIFICATE OUTPUTS
# =============================================================================

output "cluster_issuer_name" {
  description = "Name of the cluster issuer"
  value       = module.self_signed_cluster_issuer.issuer_name
}
