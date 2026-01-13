output "prometheus_url" {
  description = "Internal URL for Prometheus server (for use as Grafana data source)"
  value       = "http://prometheus-server.${var.namespace}.svc.cluster.local"
}

output "namespace" {
  description = "Namespace where Prometheus is deployed"
  value       = var.namespace
}

output "release_name" {
  description = "Name of the Prometheus Helm release"
  value       = helm_release.prometheus.name
}
