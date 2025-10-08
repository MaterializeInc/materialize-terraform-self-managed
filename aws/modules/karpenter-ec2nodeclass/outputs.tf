output "kube_reserved_memory_description" {
  description = "Quantity of memory to reserve for the kubelet."
  value       = local.kube_reserved_memory_description
}

output "kube_reserved_cpus_description" {
  description = "Quantity of CPUs to reserve for the kubelet."
  value       = local.kube_reserved_cpus_description
}
