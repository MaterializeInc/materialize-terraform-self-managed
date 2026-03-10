output "service_account_email" {
  description = "The email of the cert-manager Google service account (for annotation)."
  value       = google_service_account.cert_manager.email
}
