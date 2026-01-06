output "instance_name" {
  description = "Name of the Materialize instance"
  value       = var.instance_name
}

output "instance_namespace" {
  description = "Namespace of the Materialize instance"
  value       = var.instance_namespace
}

output "instance_resource_id" {
  description = "Resource ID of the Materialize instance"
  value       = data.kubernetes_resource.materialize_instance.object.status.resourceId
}

output "metadata_backend_url" {
  description = "Metadata backend URL used by the Materialize instance"
  value       = var.metadata_backend_url
}

output "persist_backend_url" {
  description = "Persist backend URL used by the Materialize instance"
  value       = var.persist_backend_url
}

output "mz_system_credentials" {
  description = "Credentials for the mz_system user, not to be used by applications"
  value = contains(["Password", "Sasl"], var.authenticator_kind) ? {
    username = "mz_system"
    password = var.external_login_password_mz_system
  } : {}
  sensitive = true
}

output "service_account_credentials" {
  description = "Credentials for the default service account with superuser privileges, Login to materialize using these credentials"
  value = contains(["Password", "Sasl"], var.authenticator_kind) ? {
    username = local.service_account_name
    password = random_password.service_account_password[0].result
  } : {}
  sensitive = true
}
