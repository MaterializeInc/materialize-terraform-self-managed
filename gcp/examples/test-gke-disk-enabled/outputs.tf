output "cluster_name" {
  description = "GKE cluster name"
  value       = module.gke.cluster_name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = module.gke.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  value       = module.gke.cluster_ca_certificate
  sensitive   = true
}

output "nodepool_name" {
  description = "NodePool name"
  value       = var.skip_nodepool ? null : module.nodepool[0].node_pool_name
}

output "node_service_account" {
  description = "Service account email for nodes"
  value       = module.gke.service_account_email
}