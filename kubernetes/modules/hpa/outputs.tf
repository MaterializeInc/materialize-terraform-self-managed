output "hpa_name" {
  description = "Name of the HPA resource"
  value       = kubernetes_horizontal_pod_autoscaler_v2.this.metadata[0].name
}

output "hpa_namespace" {
  description = "Namespace of the HPA resource"
  value       = kubernetes_horizontal_pod_autoscaler_v2.this.metadata[0].namespace
}
