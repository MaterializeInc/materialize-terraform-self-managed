output "service_name" {
  description = "Name of the Kubernetes Service for the selfservice UI."
  value       = kubernetes_service.ui.metadata[0].name
}

output "service_url" {
  description = "Internal URL of the selfservice UI service. Uses https when TLS is enabled."
  value       = "${local.tls_enabled ? "https" : "http"}://${var.name}.${local.namespace}.svc.cluster.local:${var.port}"
}

output "namespace" {
  description = "Namespace where the selfservice UI is deployed."
  value       = local.namespace
}

output "port" {
  description = "Port the selfservice UI listens on."
  value       = var.port
}
