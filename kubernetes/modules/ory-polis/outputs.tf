output "internal_url" {
  description = "Internal cluster URL for Polis (SSO, SCIM, OAuth endpoints). Always http because Polis itself does not terminate TLS, it runs as a NextJS app that only speaks plain HTTP on its configured port. Callers of this module are responsible for putting a TLS-terminating proxy in front, typically a cloud LoadBalancer service using cert-manager certs, a cloud-native cert like AWS ACM or GCP managed certs, or an ingress controller like nginx."
  value       = "http://${var.release_name}.${local.namespace}.svc.cluster.local:${var.port}"
}

output "external_url" {
  description = "Externally-reachable HTTPS URL for Polis, as supplied via var.external_url. This is the browser-facing URL that SAML/OAuth flows redirect through, and the issuer URL that upstream OIDC consumers (e.g., Kratos social sign-in) should point at."
  value       = var.external_url
}

output "namespace" {
  description = "Namespace where Ory Polis is deployed."
  value       = local.namespace
}

output "service_name" {
  description = "Kubernetes service name for Polis. Set from var.release_name via fullnameOverride so it stays predictable."
  value       = var.release_name
}

output "release_name" {
  description = "Helm release name."
  value       = helm_release.polis.name
}

output "admin_api_keys" {
  description = "API key for Polis admin APIs."
  value       = local.admin_api_keys
  sensitive   = true
}

output "nextauth_secret" {
  description = "NextAuth.js session signing secret."
  value       = local.nextauth_secret
  sensitive   = true
}

output "db_encryption_key" {
  description = "Symmetric key used to encrypt sensitive fields at rest in the Polis database. Persist across applies; rotating invalidates existing encrypted records."
  value       = local.db_encryption_key
  sensitive   = true
}
