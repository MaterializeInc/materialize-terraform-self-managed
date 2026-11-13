output "issuer_name" {
  description = "Name of the ClusterIssuer: `<name_prefix>-letsencrypt-staging` while it uses Let's Encrypt staging, `<name_prefix>-letsencrypt` otherwise."
  value       = kubectl_manifest.letsencrypt_cluster_issuer.name
}
