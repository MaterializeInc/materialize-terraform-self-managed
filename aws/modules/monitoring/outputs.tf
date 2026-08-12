output "namespace" {
  description = "Namespace the monitoring stack is installed into."
  value       = module.monitoring.namespace
}

output "grafana_url" {
  description = <<-EOT
    Where Grafana answers: the hostname you supplied, else the NLB's own DNS name, else the
    in-cluster Service — which means a port-forward.

    Known at plan time, because the load balancer is a Terraform resource here rather than something
    the load-balancer controller creates behind our back. Always `http`: the NLB terminates no TLS.
    Nothing here publishes DNS for a hostname you supply.
  EOT
  value = (
    try(local.grafana_lb.host, null) != null
    ? "${local.grafana_scheme}://${local.grafana_lb.host}"
    : local.grafana_load_balancer_address != null
    ? "${local.grafana_scheme}://${local.grafana_load_balancer_address}"
    : module.monitoring.grafana_url
  )
}

output "grafana_load_balancer_address" {
  description = "DNS name of the Grafana NLB, or null when Grafana is not exposed."
  value       = local.grafana_load_balancer_address
}

output "grafana_load_balancer_arn" {
  description = "ARN of the Grafana NLB, or null when Grafana is not exposed. Useful for attaching your own listeners or a WAF."
  value       = one(aws_lb.grafana[*].arn)
}

output "grafana_load_balancer_security_group_id" {
  description = "Security group governing who can reach the Grafana NLB, or null when Grafana is not exposed. The allowlist lives here rather than on the Service, because the Service stays ClusterIP."
  value       = one(aws_security_group.grafana_nlb[*].id)
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
