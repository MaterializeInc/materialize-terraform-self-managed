output "service_name" {
  description = "Name of the Kubernetes Service for the selfservice UI."
  value       = kubernetes_service.ui.metadata[0].name
}

output "service_url" {
  description = "Internal URL of the selfservice UI service. Uses https when TLS is enabled."
  value       = local.service_url
}

output "namespace" {
  description = "Namespace where the selfservice UI is deployed."
  value       = local.namespace
}

output "port" {
  description = "Port the selfservice UI listens on."
  value       = var.port
}

# Token hook -------------------------------------------------------------------
# Hydra calls POST /hooks/token on every token issuance, authenticating with a
# shared key in a header. Feed these three outputs into the ory-hydra module's
# token_hook variable. All three are null / unset when the hook is disabled.

output "token_hook_url" {
  description = "Internal URL of the Hydra token hook served by the selfservice UI. Null when token_hook_enabled is false."
  value       = var.token_hook_enabled ? "${local.service_url}/hooks/token" : null
}

output "token_hook_api_key" {
  description = "Shared secret Hydra must send when calling the token hook. Null when token_hook_enabled is false."
  value       = local.token_hook_api_key
  sensitive   = true
}

output "token_hook_api_key_header" {
  description = "HTTP header the token hook expects the API key in."
  value       = "X-Token-Hook-Api-Key"
}
