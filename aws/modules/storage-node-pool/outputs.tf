output "storage_class_name" {
  description = "StorageClass provisioned from the nodes' instance store. A workload must use this class to land on local NVMe."
  value       = var.storage_class_name
}

output "node_selector" {
  description = "Label selecting this pool's nodes."
  value       = local.node_labels
}

output "tolerations" {
  description = "Tolerations required to schedule onto this pool, which is tainted so nothing else lands there."
  value       = local.tolerations
}

output "volume_group" {
  description = "LVM volume group built from the instance store."
  value       = var.volume_group
}

output "name" {
  description = "Name of the node class and node pool."
  value       = var.name
}
