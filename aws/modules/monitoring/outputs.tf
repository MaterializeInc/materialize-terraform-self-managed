output "namespace" {
  description = "Namespace the monitoring stack is installed into."
  value       = module.monitoring.namespace
}

output "grafana_url" {
  description = "URL for Grafana: the external one when `grafana_ingress` is set, the in-cluster Service otherwise — in which case reaching it means a port-forward. DNS for an external host is yours to create; nothing here publishes it."
  value       = var.grafana_ingress == null ? module.monitoring.grafana_url : "${local.grafana_scheme}://${var.grafana_ingress.host}"
}

output "grafana_admin_password" {
  description = "Grafana admin password."
  value       = module.monitoring.grafana_admin_password
  sensitive   = true
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

output "metrics_url" {
  description = "Thanos Query endpoint. Prometheus-API-compatible."
  value       = module.monitoring.metrics_url
}

output "logs_url" {
  description = "Loki read endpoint."
  value       = module.monitoring.logs_url
}

output "logs_bucket" {
  description = "S3 bucket holding Loki chunks and the ruler's state."
  value       = aws_s3_bucket.telemetry["loki"].id
}

output "metrics_bucket" {
  description = "S3 bucket holding Thanos blocks."
  value       = aws_s3_bucket.telemetry["thanos"].id
}

output "iam_role_arns" {
  description = "IRSA role ARNs, by backend."
  value       = { for k, r in aws_iam_role.telemetry : k => r.arn }
}

output "workload_identity_subjects" {
  description = "Service-account subjects the IRSA trust policies are scoped to. Emitted by the monitoring module from the names the chart actually renders, so a mismatch with the roles above is visible rather than silent."
  value       = module.monitoring.workload_identity_subjects
}
