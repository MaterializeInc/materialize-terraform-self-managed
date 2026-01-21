output "grafana_url" {
  description = "Internal URL for Grafana"
  value       = "http://grafana.${var.namespace}.svc.cluster.local"
}

output "namespace" {
  description = "Namespace where Grafana is deployed"
  value       = var.namespace
}

output "release_name" {
  description = "Name of the Grafana Helm release"
  value       = helm_release.grafana.name
}

output "admin_password" {
  description = "Admin password for Grafana"
  value       = var.admin_password != null ? var.admin_password : random_password.grafana_admin[0].result
  sensitive   = true
}
