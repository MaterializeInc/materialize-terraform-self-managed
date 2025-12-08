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

output "network_security_group_id" {
  description = "The ID of the network security group."
  value       = var.internal ? null : azurerm_network_security_group.aks[0].id
}

output "network_security_group_name" {
  description = "The name of the network security group."
  value       = var.internal ? null : azurerm_network_security_group.aks[0].name
}
