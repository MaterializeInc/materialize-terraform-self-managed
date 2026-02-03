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

output "superuser_credentials" {
  description = "Credentials for the superuser, Login to materialize using these credentials"
  value = local.create_superuser ? {
    username = var.superuser_credentials.username
    password = local.superuser_password
  } : {}
  sensitive = true
}
