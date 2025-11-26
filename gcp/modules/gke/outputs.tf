output "cluster_name" {
  description = "The name of the GKE cluster"
  value       = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  description = "The public endpoint of the GKE cluster"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "cluster_private_endpoint" {
  description = "The private endpoint of the GKE cluster (used by nodes and VPC resources)"
  value       = google_container_cluster.primary.private_cluster_config != null && length(google_container_cluster.primary.private_cluster_config) > 0 ? google_container_cluster.primary.private_cluster_config[0].private_endpoint : null
  sensitive   = true
}

output "cluster_ca_certificate" {
  value = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
}

output "cluster_location" {
  description = "The location of the GKE cluster"
  value       = google_container_cluster.primary.location
}

output "service_account_email" {
  description = "The email of the GKE service account"
  value       = google_service_account.gke_sa.email
}

output "workload_identity_sa_email" {
  description = "The email of the Workload Identity service account"
  value       = google_service_account.workload_identity_sa.email
}
