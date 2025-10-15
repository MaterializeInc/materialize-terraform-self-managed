output "issuer_name" {
  description = "Name of the ClusterIssuer"
  value       = kubectl_manifest.root_ca_cluster_issuer.name
}
