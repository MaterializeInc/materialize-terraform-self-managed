output "deployment_name" {
  description = "Name of the custom CoreDNS deployment"
  value       = kubernetes_deployment.coredns.metadata[0].name
}

output "config_map_name" {
  description = "Name of the CoreDNS ConfigMap"
  value       = kubernetes_config_map.coredns.metadata[0].name
}

output "service_account_name" {
  description = "Name of the CoreDNS service account"
  value       = var.create_coredns_service_account ? kubernetes_service_account.coredns[0].metadata[0].name : null
}
