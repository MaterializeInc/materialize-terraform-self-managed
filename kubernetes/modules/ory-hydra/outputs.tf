output "public_url" {
  description = "Internal URL for Hydra public API (user-facing: OAuth2 authorize, token, OIDC discovery)"
  value       = "http://${var.release_name}-public.${local.namespace}.svc.cluster.local:4444"
}

output "admin_url" {
  description = "Internal URL for Hydra admin API (privileged: OAuth2 client management, consent/login flow management)"
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

output "maester_pod_labels" {
  description = "Labels on the Hydra Maester pods, e.g. for NetworkPolicies that admit Maester to Hydra's admin port. The chart names them after the subchart's fullname."
  value = {
    "app.kubernetes.io/name"     = strcontains(var.release_name, "hydra-maester") ? var.release_name : trimsuffix(substr("${var.release_name}-hydra-maester", 0, 63), "-")
    "app.kubernetes.io/instance" = var.release_name
  }
}
