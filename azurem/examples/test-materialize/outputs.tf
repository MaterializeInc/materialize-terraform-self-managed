output "external_login_password" {
  description = "The external login password for the Materialize instance"
  value       = random_password.external_login_password_mz_system.result
  sensitive   = true
}

output "instance_resource_id" {
  description = "The resource ID of the Materialize instance"
  value       = var.install_materialize_instance ? module.materialize_instance[0].instance_resource_id : null
}

output "metadata_backend_url" {
  description = "The metadata backend URL of the Materialize instance"
  value       = var.install_materialize_instance ? module.materialize_instance[0].metadata_backend_url : null
  sensitive   = true
}

output "persist_backend_url" {
  description = "The persist backend URL of the Materialize instance"
  value       = var.install_materialize_instance ? module.materialize_instance[0].persist_backend_url : null
}

output "instance_installed" {
  description = "Whether the Materialize instance is installed"
  value       = var.install_materialize_instance
}

# Storage outputs
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

# Load balancer outputs
output "load_balancer_installed" {
  description = "Whether the load balancer is installed"
  value       = var.install_materialize_instance
}

output "console_load_balancer_ip" {
  description = "IP address of load balancer pointing at the web console"
  value       = var.install_materialize_instance ? module.load_balancers[0].console_load_balancer_ip : null
}

output "balancerd_load_balancer_ip" {
  description = "IP address of load balancer pointing at balancerd"
  value       = var.install_materialize_instance ? module.load_balancers[0].balancerd_load_balancer_ip : null
}

# Certificate outputs
output "cluster_issuer_name" {
  description = "Name of the cluster issuer"
  value       = var.install_materialize_instance ? module.self_signed_cluster_issuer[0].issuer_name : null
}

# Operator outputs
output "operator_namespace" {
  description = "Materialize operator namespace"
  value       = var.operator_namespace
}

