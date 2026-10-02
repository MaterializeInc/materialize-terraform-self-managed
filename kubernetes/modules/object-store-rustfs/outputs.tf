output "persist_backend_url" {
  description = "S3 connection URL for this store, in the form `materialize-instance` expects for `persist_backend_url`."
  value       = "s3://${var.access_key}:${local.secret_key}@${var.bucket}/${var.name}?endpoint=${urlencode(local.endpoint)}&region=${var.region}"
  sensitive   = true
}

output "endpoint" {
  description = "In-cluster S3 endpoint for the store."
  value       = local.endpoint
}

output "bucket" {
  description = "Bucket created for persist data."
  value       = var.bucket
}

output "namespace" {
  description = "Namespace the store runs in."
  value       = local.namespace
}

output "service_name" {
  description = "Name of the ClusterIP service clients should connect to."
  value       = kubernetes_service.this.metadata[0].name
}

output "credentials_secret_name" {
  description = "Secret holding the store's root credentials, with `access_key` and `secret_key` keys."
  value       = kubernetes_secret.credentials.metadata[0].name
}

output "access_key" {
  description = "Root access key for the store."
  value       = var.access_key
}

output "secret_key" {
  description = "Root secret key for the store."
  value       = local.secret_key
  sensitive   = true
}

output "drive_count" {
  description = "Total number of drives in the store, which is what RustFS erasure-codes across."
  value       = var.replicas * var.drives_per_replica
}

output "node_selector" {
  description = "Node selector the store was pinned with, for co-locating a benchmark client with it."
  value       = var.node_selector
}

output "tolerations" {
  description = "Tolerations the store was given, which a benchmark client needs to share its nodes."
  value       = var.tolerations
}
