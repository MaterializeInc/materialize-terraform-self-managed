output "public_url" {
  description = "Internal URL for Hydra public API (OAuth2 endpoints)"
  value       = "http://${var.release_name}-public.${local.namespace}.svc.cluster.local:4444"
}

output "admin_url" {
  description = "Internal URL for Hydra admin API"
  value       = "http://${var.release_name}-admin.${local.namespace}.svc.cluster.local:4445"
}

output "namespace" {
  description = "Namespace where Ory Hydra is deployed"
  value       = local.namespace
}

output "release_name" {
  description = "Name of the Ory Hydra Helm release"
  value       = helm_release.hydra.name
}

output "release_status" {
  description = "Status of the Ory Hydra Helm release"
  value       = helm_release.hydra.status
}

output "secrets_system" {
  description = "System secret used by Hydra"
  value       = local.secrets_system
  sensitive   = true
}

output "secrets_cookie" {
  description = "Cookie secret used by Hydra"
  value       = local.secrets_cookie
  sensitive   = true
}
