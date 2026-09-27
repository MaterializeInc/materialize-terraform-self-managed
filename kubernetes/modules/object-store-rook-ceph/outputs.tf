output "persist_backend_url" {
  description = "S3 connection URL for this store, in the form `materialize-instance` expects for `persist_backend_url`."
  value       = "s3://${data.kubernetes_secret.object_store_user.data["AccessKey"]}:${data.kubernetes_secret.object_store_user.data["SecretKey"]}@${var.bucket}/${var.name}?endpoint=${urlencode(local.endpoint)}&region=${var.region}"
  sensitive   = true
}

output "endpoint" {
  description = "In-cluster S3 endpoint for the RGW gateway."
  value       = local.endpoint
}

output "bucket" {
  description = "Bucket created for persist data."
  value       = var.bucket
}

output "namespace" {
  description = "Namespace Rook and Ceph run in."
  value       = local.namespace
}

output "credentials_secret_name" {
  description = "Secret Rook generated for the object store user, with `AccessKey` and `SecretKey` keys."
  value       = local.user_secret_name
}

output "access_key" {
  description = "Access key for the object store user."
  value       = data.kubernetes_secret.object_store_user.data["AccessKey"]
  sensitive   = true
}

output "secret_key" {
  description = "Secret key for the object store user."
  value       = data.kubernetes_secret.object_store_user.data["SecretKey"]
  sensitive   = true
}

output "object_store_name" {
  description = "Name of the CephObjectStore, which is also the suffix of the gateway service."
  value       = var.name
}

output "node_selector" {
  description = "Node selector the store was pinned with, for co-locating a benchmark client with it."
  value       = var.node_selector
}

output "tolerations" {
  description = "Tolerations the store was given, which a benchmark client needs to share its nodes."
  value       = var.tolerations
}
