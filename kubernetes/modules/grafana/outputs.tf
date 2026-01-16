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
  description = "Admin password for Grafana (retrieve with: kubectl get secret grafana -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d)"
  value       = var.admin_password != null ? var.admin_password : "Generated - retrieve from Kubernetes secret"
  sensitive   = true
}
