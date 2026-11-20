output "bucket_name" {
  description = "The name of the GCS bucket"
  value       = google_storage_bucket.materialize.name
}

output "bucket_url" {
  description = "The URL of the GCS bucket"
  value       = google_storage_bucket.materialize.url
}

output "bucket_self_link" {
  description = "The self_link of the GCS bucket"
  value       = google_storage_bucket.materialize.self_link
}

output "hmac_access_id" {
  description = "Access ID of the HMAC key, or null when create_hmac_key is false"
  value       = one(google_storage_hmac_key.materialize[*].access_id)
  sensitive   = true
}

output "hmac_secret" {
  description = "Secret of the HMAC key, or null when create_hmac_key is false"
  value       = one(google_storage_hmac_key.materialize[*].secret)
  sensitive   = true
}

output "workload_identity_service_account_email" {
  description = "Google service account the instance's Kubernetes service account impersonates for native access, or null when workload_identity is unset. Set it as the instance's iam.gke.io/gcp-service-account annotation."
  value       = one(google_service_account.persist[*].email)
}

output "persist_backend_url" {
  description = "Native persist URL (gcs://<bucket>/<persist_path>), or null when workload_identity is unset"
  value       = var.workload_identity != null ? "gcs://${google_storage_bucket.materialize.name}/${var.persist_path}" : null
}
