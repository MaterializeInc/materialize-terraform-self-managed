output "client_id" {
  description = "The client ID of the managed identity (for annotation)."
  value       = azurerm_user_assigned_identity.cert_manager.client_id
}
