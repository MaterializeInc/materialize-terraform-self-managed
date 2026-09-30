output "namespace" {
  description = "The monitoring namespace, once it exists."
  value       = var.create_namespace ? kubernetes_namespace.monitoring[0].metadata[0].name : var.namespace
}

output "crds_installed" {
  description = <<-EOT
    Whether this module installed the monitoring CRDs.

    Pass it to a module's ServiceMonitor toggle rather than a literal: it is read from the release,
    so anything that uses it waits for the CRDs to exist.
  EOT
  value       = length(helm_release.crds) > 0
}
