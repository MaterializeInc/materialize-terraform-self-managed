output "instance_group" {
  description = "Self link of the connector instance group."
  value       = google_compute_region_instance_group_manager.connector.instance_group
}

output "service_account_email" {
  description = "Service account the connectors run as."
  value       = google_service_account.connector.email
}

output "tunnel_token_secret" {
  description = "Secret Manager secret holding the tunnel token."
  value       = google_secret_manager_secret.tunnel_token.id
}
