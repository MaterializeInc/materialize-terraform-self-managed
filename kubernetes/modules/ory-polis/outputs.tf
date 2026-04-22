output "url" {
  description = "Internal cluster URL for Polis (SSO, SCIM, OAuth endpoints). Always http because Polis does not serve TLS itself — TLS is terminated externally in front of the pod."
  value       = "http://${var.name}.${local.namespace}.svc.cluster.local:${var.port}"
}

output "external_url" {
  description = "Externally-reachable HTTPS URL for Polis, as supplied via var.external_url. This is the browser-facing URL that SAML/OAuth flows redirect through, and the issuer URL that upstream OIDC consumers (e.g., Kratos social sign-in) should point at."
  value       = var.external_url
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
