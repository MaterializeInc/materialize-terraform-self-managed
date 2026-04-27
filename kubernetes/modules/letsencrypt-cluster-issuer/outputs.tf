output "issuer_name" {
  description = "Name of the ClusterIssuer that was created."
  value       = kubectl_manifest.cluster_issuer.name
}

output "issuer_kind" {
  description = "Kind of the issuer (always ClusterIssuer)."
  value       = "ClusterIssuer"
}

output "issuer_ref" {
  description = "Reference object suitable for passing to modules that accept a cert-manager issuer reference."
  value = {
    name = kubectl_manifest.cluster_issuer.name
    kind = "ClusterIssuer"
  }
}
