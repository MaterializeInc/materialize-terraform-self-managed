output "balancerd_ip" {
  description = "The reserved static IP address for balancerd."
  value       = google_compute_address.balancerd.address
}

output "console_ip" {
  description = "The reserved static IP address for console."
  value       = google_compute_address.console.address
}
