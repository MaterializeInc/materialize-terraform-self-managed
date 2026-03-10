output "balancerd_fqdn" {
  description = "The FQDN of the balancerd DNS record."
  value       = azurerm_dns_a_record.balancerd.fqdn
}

output "console_fqdn" {
  description = "The FQDN of the console DNS record."
  value       = azurerm_dns_a_record.console.fqdn
}
