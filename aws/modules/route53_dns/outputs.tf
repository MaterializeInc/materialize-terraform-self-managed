output "balancerd_fqdn" {
  description = "The FQDN of the balancerd DNS record."
  value       = aws_route53_record.balancerd.fqdn
}

output "console_fqdn" {
  description = "The FQDN of the console DNS record."
  value       = aws_route53_record.console.fqdn
}
