# Outputs for GitHub Actions configuration
output "client_id" {
  description = "Azure AD Application (Client) ID for GitHub Actions"
  value       = azuread_application.github_actions.client_id
}

output "service_principal_object_id" {
  description = "Object ID of the Service Principal for GitHub Actions"
  value       = azuread_service_principal.github_actions.object_id
}

output "tenant_id" {
  description = "Azure Tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  description = "Azure Subscription ID"
  value       = data.azurerm_client_config.current.subscription_id
}
