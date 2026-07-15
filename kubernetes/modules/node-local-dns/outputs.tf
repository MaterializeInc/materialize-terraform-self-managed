output "release_name" {
  description = "Name of the node-local-dns helm release"
  value       = helm_release.node_local_dns.name
}

output "namespace" {
  description = "Namespace the node-local-dns DaemonSet runs in"
  value       = helm_release.node_local_dns.namespace
}

output "daemonset_name" {
  description = "Name of the node-local-dns DaemonSet"
  value       = "node-local-dns"
}
