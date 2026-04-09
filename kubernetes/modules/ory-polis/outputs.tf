output "url" {
  description = "Internal URL for Polis (SSO, SCIM, OAuth endpoints)"
  value       = "http://${var.name}.${local.namespace}.svc.cluster.local:${var.port}"
}

output "namespace" {
  description = "Namespace where Ory Polis is deployed"
  value       = local.namespace
}

output "jackson_api_keys" {
  description = "API key for Polis admin APIs"
  value       = local.jackson_api_keys
  sensitive   = true
}

output "nextauth_secret" {
  description = "NextAuth.js session signing secret"
  value       = local.nextauth_secret
  sensitive   = true
}
