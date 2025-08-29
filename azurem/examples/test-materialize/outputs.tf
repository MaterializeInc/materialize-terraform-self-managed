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
}

output "persist_backend_url" {
  description = "The persist backend URL of the Materialize instance"
  value       = var.install_materialize_instance ? module.materialize_instance[0].persist_backend_url : null
}

output "operator_installed" {
  description = "Whether the Materialize operator is installed"
  value       = var.install_materialize_operator
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

output "storage_account_key" {
  description = "The primary access key for the storage account"
  value       = module.storage.storage_account_key
  sensitive   = true
}

output "storage_primary_blob_endpoint" {
  description = "The primary blob endpoint of the storage account"
  value       = module.storage.primary_blob_endpoint
}

output "storage_primary_blob_sas_token" {
  description = "The primary blob SAS token for the storage account"
  value       = module.storage.primary_blob_sas_token
  sensitive   = true
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

