output "nodepool_name" {
  description = "The name of the Karpenter NodePool"
  value       = var.name
}

output "nodeclass_name" {
  description = "The name of the AKSNodeClass"
  value       = var.name
}
