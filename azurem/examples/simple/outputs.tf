output "vnet_id" {
  value = module.networking.vnet_id
}

output "vnet_name" {
  value = module.networking.vnet_name
}

output "aks_subnet_id" {
  value = module.networking.aks_subnet_id
}

output "postgres_subnet_id" {
  value = module.networking.postgres_subnet_id
}

output "private_dns_zone_id" {
  value = module.networking.private_dns_zone_id
}

output "nat_gateway_id" {
  value = module.networking.nat_gateway_id
}

output "nat_gateway_public_ip" {
  value = module.networking.nat_gateway_public_ip
}

output "vnet_address_space" {
  value = module.networking.vnet_address_space
}

output "resource_group_name" {
  value = azurerm_resource_group.materialize.name
}

# AKS Outputs
output "aks_cluster_name" {
  description = "The name of the AKS cluster"
  value       = module.aks.cluster_name
}

output "aks_cluster_id" {
  description = "The ID of the AKS cluster"
  value       = module.aks.cluster_id
}

output "aks_cluster_fqdn" {
  description = "The FQDN of the AKS cluster"
  value       = module.aks.cluster_fqdn
}

output "aks_kube_config" {
  description = "The kube config of the AKS cluster"
  value       = module.aks.kube_config
  sensitive   = true
}

output "aks_cluster_endpoint" {
  description = "The endpoint of the AKS cluster"
  value       = module.aks.cluster_endpoint
  sensitive   = true
}

output "aks_workload_identity_client_id" {
  description = "The client ID of the workload identity"
  value       = module.aks.workload_identity_client_id
}

output "aks_oidc_issuer_url" {
  description = "The OIDC issuer URL of the AKS cluster"
  value       = module.aks.cluster_oidc_issuer_url
}

# Node Pool Outputs
output "materialize_nodepool_name" {
  description = "The name of the Materialize node pool"
  value       = module.nodepool.nodepool_name
}
