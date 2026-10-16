output "instance_name" {
  description = "The name of the Materialize instance."
  value       = var.instance_name
}

output "console_load_balancer_ip" {
  description = "IP address of load balancer pointing at the web console."
  value       = kubernetes_service.console_load_balancer.status[0].load_balancer[0].ingress[0].ip
}

output "balancerd_load_balancer_ip" {
  description = "IP address of load balancer pointing at balancerd."
  value       = kubernetes_service.balancerd_load_balancer.status[0].load_balancer[0].ingress[0].ip
}

output "forwarding_rule_names" {
  description = "Names of the forwarding rules GKE made for the console and balancerd load balancers, which the monitoring module's `provider_metrics.forwarding_rules` takes."
  value       = sort([for rule in data.google_compute_forwarding_rules.load_balancers.rules : rule.name if contains(local.load_balancer_ips, rule.ip_address)])
}
