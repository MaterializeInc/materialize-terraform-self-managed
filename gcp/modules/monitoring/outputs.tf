output "namespace" {
  description = "Namespace the monitoring stack is installed into."
  value       = module.monitoring.namespace
}

output "grafana_url" {
  description = <<-EOT
    Where Grafana answers, in preference order: the hostname you supplied, else the load balancer's
    own address once the cloud has assigned one, else the in-cluster Service — which means a
    port-forward.

    A load balancer's address is assigned asynchronously, so immediately after the first apply this
    can still report the in-cluster name; the next plan picks it up. Nothing here publishes DNS for a
    hostname you supply. Always `http`: an L4 load balancer terminates no TLS.
  EOT
  value = (
    try(var.grafana_load_balancer.host, null) != null
    ? "${local.grafana_scheme}://${var.grafana_load_balancer.host}"
    : local.grafana_load_balancer_address != null
    ? "${local.grafana_scheme}://${local.grafana_load_balancer_address}"
    : module.monitoring.grafana_url
  )
}

output "grafana_load_balancer_address" {
  description = "The Grafana load balancer's IP or hostname, or null when it is not exposed or the cloud has not assigned one yet."
  value       = local.grafana_load_balancer_address
}

output "grafana_database_endpoint" {
  description = "`host:port` of the database backing Grafana's state, or null when Grafana is on SQLite."
  value       = local.grafana_database_host == null ? null : "${local.grafana_database_host}:${local.grafana_database_port}"
}

output "grafana_database_password" {
  description = "Password for the Grafana database user. Generated when this module creates the instance."
  value       = local.grafana_database_effective_password
  sensitive   = true
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
