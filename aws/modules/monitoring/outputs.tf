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
