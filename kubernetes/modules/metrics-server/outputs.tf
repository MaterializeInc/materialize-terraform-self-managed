output "namespace" {
  description = "Namespace where metrics-server is deployed"
  value       = local.namespace
}

output "release_name" {
  description = "Name of the metrics-server Helm release"
  value       = helm_release.metrics_server.name
}
