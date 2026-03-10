output "issuer_name" {
  description = "The name of the ACME ClusterIssuer."
  value       = "${var.name_prefix}-acme"
}
