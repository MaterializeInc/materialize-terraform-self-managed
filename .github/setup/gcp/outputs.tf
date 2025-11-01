# Outputs for GitHub Actions configuration
output "workload_identity_provider" {
  description = "Full resource name of the Workload Identity Provider for GitHub Actions"
  value       = google_iam_workload_identity_pool_provider.github_actions.name
}

output "workload_identity_pool" {
  description = "Full resource name of the Workload Identity Pool"
  value       = google_iam_workload_identity_pool.github_actions.name
}

output "service_account_email" {
  description = "Email address of the GitHub Actions Service Account"
  value       = google_service_account.github_actions.email
}
