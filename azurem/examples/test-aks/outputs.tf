output "cluster_name" {
  description = "The name of the AKS cluster"
  value       = module.aks.cluster_name
}

output "cluster_id" {
  description = "The ID of the AKS cluster"
  value       = module.aks.cluster_id
}

output "cluster_fqdn" {
  description = "The FQDN of the AKS cluster"
  value       = module.aks.cluster_fqdn
}

output "cluster_endpoint" {
  description = "The endpoint of the AKS cluster"
  value       = module.aks.cluster_endpoint
  sensitive   = true
}

output "kube_config" {
  description = "The kube config of the AKS cluster"
  value       = module.aks.kube_config
  sensitive   = true
}

output "workload_identity_client_id" {
  description = "The client ID of the workload identity"
  value       = module.aks.workload_identity_client_id
}

output "cluster_oidc_issuer_url" {
  description = "The OIDC issuer URL of the AKS cluster"
  value       = module.aks.cluster_oidc_issuer_url
}

output "cluster_identity_principal_id" {
  description = "The principal ID of the cluster identity"
  value       = module.aks.cluster_identity_principal_id
}

output "nodepool_name" {
  description = "The name of the Materialize node pool"
  value       = module.nodepool.nodepool_name
}

