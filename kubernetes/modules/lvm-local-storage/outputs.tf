output "storage_class_name" {
  description = "Name of the StorageClass backed by the instance store volume group."
  value       = kubernetes_storage_class.instance_store.metadata[0].name
}

output "volume_group" {
  description = "LVM volume group the StorageClass provisions from."
  value       = var.volume_group
}

output "namespace" {
  description = "Namespace the CSI driver runs in."
  value       = local.namespace
}
