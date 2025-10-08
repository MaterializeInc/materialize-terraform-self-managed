output "issuer_name" {
  description = "Name of the ClusterIssuer"
  value       = kubernetes_manifest.root_ca_cluster_issuer.object.metadata.name
}
