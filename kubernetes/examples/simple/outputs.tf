output "materialize_instance_name" {
  description = "Materialize instance name"
  value       = module.materialize_instance.instance_name
}

output "materialize_instance_namespace" {
  description = "Materialize instance namespace"
  value       = module.materialize_instance.instance_namespace
}

output "external_login_password_mz_system" {
  description = "Password for the external login to the Materialize instance"
  value       = random_password.external_login_password_mz_system.result
  sensitive   = true
}

# There is no cloud load balancer here; reach SQL by port-forwarding this
# service (port 6875) or by exposing it in whatever way fits your cluster.
output "balancerd_service_name" {
  description = "Name of the balancerd service for the Materialize instance"
  value       = "mz${module.materialize_instance.instance_resource_id}-balancerd"
}
