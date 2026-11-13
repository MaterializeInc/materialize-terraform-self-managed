output "issuer_name" {
  description = "Name of the ClusterIssuer"
  value       = kubectl_manifest.letsencrypt_cluster_issuer.name
}
