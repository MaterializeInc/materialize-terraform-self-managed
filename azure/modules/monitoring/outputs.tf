output "namespace" {
  description = "Namespace the monitoring stack is installed into."
  value       = module.monitoring.namespace
}

output "grafana_url" {
  description = "In-cluster URL for Grafana. Grafana is ClusterIP-only today, so reaching it means a port-forward."
  value       = module.monitoring.grafana_url
}

output "grafana_admin_password" {
  description = "Grafana admin password."
  value       = module.monitoring.grafana_admin_password
  sensitive   = true
}

output "metrics_url" {
  description = "Thanos Query endpoint. Prometheus-API-compatible."
  value       = module.monitoring.metrics_url
}

output "logs_url" {
  description = "Loki read endpoint."
  value       = module.monitoring.logs_url
}

output "storage_account_name" {
  description = "Storage account holding both telemetry containers."
  value       = azurerm_storage_account.telemetry.name
}

output "logs_container" {
  description = "Blob container holding Loki chunks and the ruler's state."
  value       = azurerm_storage_container.telemetry["loki"].name
}

output "metrics_container" {
  description = "Blob container holding Thanos blocks."
  value       = azurerm_storage_container.telemetry["thanos"].name
}

output "identity_client_ids" {
  description = "User-assigned identity client IDs, by backend. One per backend, each scoped to its own container."
  value       = { for k, id in azurerm_user_assigned_identity.telemetry : k => id.client_id }
}

output "workload_identity_subjects" {
  description = "The `system:serviceaccount:<namespace>:<sa>` subjects the federated credentials trust. Emitted so a mismatch against the chart's rendered ServiceAccount names is visible rather than derived."
  value       = module.monitoring.workload_identity_subjects
}
