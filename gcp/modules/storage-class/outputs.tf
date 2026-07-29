output "storage_class_name" {
  description = "Name of the created storage class, or the configured name if creation was skipped"
  value       = var.create_storage_class ? kubernetes_storage_class.pd_ssd[0].metadata[0].name : var.storage_class_name
}
