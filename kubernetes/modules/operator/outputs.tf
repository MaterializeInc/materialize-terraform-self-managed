output "operator_namespace" {
  description = "Namespace where the operator is installed"
  value       = local.operator_namespace
}

output "operator_release_name" {
  description = "Helm release name of the operator"
  value       = helm_release.materialize_operator.name
}

output "operator_release_status" {
  description = "Status of the helm release"
  value       = helm_release.materialize_operator.status
}

output "monitoring_namespace" {
  description = "Namespace where monitoring resources are installed"
  value       = local.monitoring_namespace
}
