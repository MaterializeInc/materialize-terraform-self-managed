output "persist_backend_url" {
  description = "S3 connection URL for the store, in the form `materialize-instance` expects for `persist_backend_url`."
  value       = module.ceph.persist_backend_url
  sensitive   = true
}

output "endpoint" {
  description = "In-cluster S3 endpoint for the RGW gateway."
  value       = module.ceph.endpoint
}

output "bucket" {
  description = "Bucket created for persist data."
  value       = module.ceph.bucket
}

output "namespace" {
  description = "Namespace Rook and Ceph run in."
  value       = module.ceph.namespace
}

output "storage_class_name" {
  description = "StorageClass backing the OSDs, provisioned from the nodes' instance store."
  value       = module.storage_pool.storage_class_name
}

output "node_selector" {
  description = "Label selecting the storage nodes, for pinning a benchmark client alongside the store."
  value       = module.storage_pool.node_selector
}

output "tolerations" {
  description = "Tolerations needed to schedule onto the storage nodes."
  value       = module.storage_pool.tolerations
}
