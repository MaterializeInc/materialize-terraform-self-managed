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

output "ory" {
  description = "The Ory stack's in-cluster endpoints, or null when enable_ory is false. services maps each component to its Service (port 443) and the hostname its TLS certificate is issued for."
  value = var.enable_ory ? {
    namespace                 = local.ory_namespace
    issuer                    = module.ory[0].hydra_external_url
    oauth2_client_secret_name = module.ory[0].oauth2_client_secret_name
    services = {
      for role, host in local.ory_hosts : role => {
        name = split(".", host)[0]
        host = host
      } if role != "polis" || var.ory_enable_polis
    }
  } : null
}
