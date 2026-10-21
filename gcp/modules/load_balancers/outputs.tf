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
  description = "Names of the forwarding rules GKE made for the load balancers, keyed `console` and `balancerd`, whose values the monitoring module's `provider_metrics.forwarding_rules` takes."
  # One rule per Service: GKE makes a rule per protocol, and both Services are
  # TCP only. A Service whose rule is not found yet is left out.
  value = {
    for service, names in {
      for service, ip in local.load_balancer_ips :
      service => [for rule in data.google_compute_forwarding_rules.load_balancers.rules : rule.name if rule.ip_address == ip]
    } : service => one(names) if length(names) > 0
  }
}
