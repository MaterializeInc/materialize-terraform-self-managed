output "balancerd_fqdn" {
  description = "The FQDN of the balancerd DNS record."
  value       = trimsuffix(google_dns_record_set.balancerd.name, ".")
}

output "console_fqdn" {
  description = "The FQDN of the console DNS record."
  value       = trimsuffix(google_dns_record_set.console.name, ".")
}
