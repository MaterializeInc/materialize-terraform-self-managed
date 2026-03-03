output "public_url" {
  description = "Internal URL for Kratos public API"
  value       = "http://${var.release_name}-public.${local.namespace}.svc.cluster.local"
}

output "admin_url" {
  description = "Internal URL for Kratos admin API"
  value       = "http://${var.release_name}-admin.${local.namespace}.svc.cluster.local"
}

output "namespace" {
  description = "Namespace where Ory Kratos is deployed"
  value       = local.namespace
}

output "release_name" {
  description = "Name of the Ory Kratos Helm release"
  value       = helm_release.kratos.name
}

output "release_status" {
  description = "Status of the Ory Kratos Helm release"
  value       = helm_release.kratos.status
}

output "secrets_default" {
  description = "Default secret used by Kratos"
  value       = local.secrets_default
  sensitive   = true
}

output "secrets_cookie" {
  description = "Cookie secret used by Kratos"
  value       = local.secrets_cookie
  sensitive   = true
}

output "secrets_cipher" {
  description = "Cipher secret used by Kratos"
  value       = local.secrets_cipher
  sensitive   = true
}
