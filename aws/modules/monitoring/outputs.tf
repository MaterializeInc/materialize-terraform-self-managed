output "namespace" {
  description = "Namespace the monitoring stack is installed into."
  value       = module.monitoring.namespace
}

output "grafana_url" {
  description = <<-EOT
    Where Grafana answers, in preference order: the hostname you supplied, else the load balancer's
    own address once AWS has assigned one, else the in-cluster Service — which means a port-forward.

    A load balancer's address is assigned asynchronously, so immediately after the first apply this
    can still report the in-cluster name; the next plan picks it up. Always `http`: the NLB
    terminates no TLS. Nothing here publishes DNS for a hostname you supply.
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
  description = "The Grafana load balancer's DNS name or IP, or null when it is not exposed or AWS has not assigned one yet."
  value       = local.grafana_load_balancer_address
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
