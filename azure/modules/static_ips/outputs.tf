output "balancerd_ip_address" {
  description = "The static IP address for balancerd."
  value       = azurerm_public_ip.balancerd.ip_address
}

output "console_ip_address" {
  description = "The static IP address for console."
  value       = azurerm_public_ip.console.ip_address
}
