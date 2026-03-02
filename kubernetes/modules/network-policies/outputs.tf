output "operator_policies" {
  description = "Network policies created in the operator namespace"
  value = compact([
    var.enable_default_deny ? "default-deny-all" : null,
    var.enable_default_deny ? "allow-all-egress" : null,
  ])
}

output "instance_policies" {
  description = "Network policies created in instance namespaces"
  value = var.enable_default_deny && length(var.instance_namespaces) > 0 ? [
    "default-deny-all",
    "allow-all-egress",
    "allow-from-operator",
  ] : []
}
