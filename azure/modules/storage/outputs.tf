output "storage_account_name" {
  description = "The name of the storage account"
  value       = azurerm_storage_account.materialize.name
}

output "container_name" {
  description = "The name of the storage container"
  value       = azurerm_storage_container.materialize.name
}

output "primary_blob_endpoint" {
  description = "The primary blob endpoint"
  value       = azurerm_storage_account.materialize.primary_blob_endpoint
}

output "federated_identity_credential_id" {
  description = "The ID of the federated identity credential for workload identity"
  value       = azurerm_federated_identity_credential.materialize_storage.id
}
