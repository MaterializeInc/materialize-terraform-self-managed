# Storage outputs
output "storage_bucket_name" {
  description = "Name of the storage bucket"
  value       = module.storage.bucket_name
}

output "storage_bucket_url" {
  description = "URL of the storage bucket"
  value       = module.storage.bucket_url
}

output "storage_hmac_access_id" {
  description = "HMAC access ID for storage"
  value       = module.storage.hmac_access_id
  sensitive   = true
}

output "storage_hmac_secret" {
  description = "HMAC secret for storage"
  value       = module.storage.hmac_secret
  sensitive   = true
}

# Certificate outputs
output "cluster_issuer_name" {
  description = "Name of the cluster issuer"
  value       = var.install_materialize_instance ? module.self_signed_cluster_issuer[0].issuer_name : null
}

# Operator outputs
output "operator_namespace" {
  description = "Materialize operator namespace"
  value       = var.operator_namespace
}

# Instance outputs
output "instance_installed" {
  description = "Whether Materialize instance was installed"
  value       = var.install_materialize_instance
}

output "instance_resource_id" {
  description = "Materialize instance resource ID"
  value       = var.install_materialize_instance ? module.materialize_instance[0].instance_resource_id : null
}

output "console_load_balancer_ip" {
  description = "Console load balancer IP for external access"
  value       = var.install_materialize_instance ? module.load_balancers[0].console_load_balancer_ip : null
}

output "balancerd_load_balancer_ip" {
  description = "Balancerd load balancer IP for external access"
  value       = var.install_materialize_instance ? module.load_balancers[0].balancerd_load_balancer_ip : null
}

# Pass through cluster info
output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = var.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  value       = var.cluster_ca_certificate
}
