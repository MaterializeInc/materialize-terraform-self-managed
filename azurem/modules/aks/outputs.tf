output "cluster_name" {
  description = "The name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "cluster_endpoint" {
  description = "The endpoint of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.kube_config[0].host
  sensitive   = true
}

output "cluster_location" {
  description = "The location of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.location
}

output "cluster_identity_principal_id" {
  description = "The principal ID of the AKS cluster identity"
  value       = azurerm_user_assigned_identity.aks_identity.principal_id
}


output "workload_identity_principal_id" {
  description = "The principal ID of the workload identity"
  value       = azurerm_user_assigned_identity.workload_identity.principal_id
}

output "kube_config" {
  description = "The kube_config for the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.kube_config
  sensitive   = true
}

output "kube_config_raw" {
  description = "The raw kube_config for the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive   = true
}

output "cluster_id" {
  description = "The ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.id
}

output "cluster_resource_group_name" {
  description = "The resource group name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.resource_group_name
}

output "cluster_fqdn" {
  description = "The FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.fqdn
}

output "cluster_private_fqdn" {
  description = "The private FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.private_fqdn
}

output "cluster_portal_fqdn" {
  description = "The portal FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.portal_fqdn
}

output "cluster_kubernetes_version" {
  description = "The version of Kubernetes used by the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.kubernetes_version
}

output "cluster_node_resource_group" {
  description = "The resource group containing the AKS cluster nodes"
  value       = azurerm_kubernetes_cluster.aks.node_resource_group
}

output "cluster_oidc_issuer_url" {
  description = "The OIDC issuer URL of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.oidc_issuer_url
}

output "workload_identity_client_id" {
  description = "The client ID of the workload identity"
  value       = azurerm_user_assigned_identity.workload_identity.client_id
}

output "workload_identity_id" {
  description = "The ID of the workload identity"
  value       = azurerm_user_assigned_identity.workload_identity.id
}

output "cluster_identity_client_id" {
  description = "The client ID of the AKS cluster identity"
  value       = azurerm_user_assigned_identity.aks_identity.client_id
}

output "cluster_identity_id" {
  description = "The ID of the AKS cluster identity"
  value       = azurerm_user_assigned_identity.aks_identity.id
}
