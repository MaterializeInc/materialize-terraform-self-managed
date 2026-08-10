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

output "logs_bucket" {
  description = "GCS bucket holding Loki chunks and the ruler's state."
  value       = google_storage_bucket.telemetry["loki"].name
}

output "metrics_bucket" {
  description = "GCS bucket holding Thanos blocks."
  value       = google_storage_bucket.telemetry["thanos"].name
}

output "service_account_emails" {
  description = "Google service account emails, by backend."
  value       = { for k, sa in google_service_account.telemetry : k => sa.email }
}

output "workload_identity_subjects" {
  description = "Kubernetes service-account subjects the Workload Identity bindings are scoped to. Emitted by the monitoring module from the names the chart actually renders, so a mismatch with the bindings above is visible rather than silent."
  value       = module.monitoring.workload_identity_subjects
}
