output "internal_url" {
  description = "Internal cluster URL for Talos. Both the admin plane (key issuance / rotation / revocation) and the data plane (verify, batchVerify, selfRevoke) share this base URL. The admin plane has no built-in auth and must stay cluster-internal; only the verify and self-revoke endpoints are safe to expose externally."
  value       = "http://${var.name}.${local.namespace}.svc.cluster.local:${var.http_port}"
}

output "metrics_url" {
  description = "Internal URL for the Talos metrics endpoint. Commercial feature."
  value       = "http://${var.name}.${local.namespace}.svc.cluster.local:${var.metrics_port}"
}

output "namespace" {
  description = "Namespace where Talos is deployed."
  value       = local.namespace
}

output "service_name" {
  description = "Kubernetes service name for Talos."
  value       = kubernetes_service.talos.metadata[0].name
}

output "credentials_issuer" {
  description = "Issuer claim Talos uses in derived JWTs. Wire this into downstream OIDC consumers (e.g., Materialize's oidc_issuer) so they validate Talos-issued tokens."
  value       = var.credentials_issuer
}

output "default_secret" {
  description = "Talos default-component secret."
  value       = local.default_secret
  sensitive   = true
}

output "hmac_secret" {
  description = "Talos HMAC secret used for API key generation."
  value       = local.hmac_secret
  sensitive   = true
}

output "pagination_secret" {
  description = "Talos pagination-token signing secret."
  value       = local.pagination_secret
  sensitive   = true
}
