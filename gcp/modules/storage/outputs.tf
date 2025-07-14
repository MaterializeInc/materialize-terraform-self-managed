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
  value     = google_storage_hmac_key.materialize.access_id
  sensitive = true
}

output "hmac_secret" {
  value     = google_storage_hmac_key.materialize.secret
  sensitive = true
}
