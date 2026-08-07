output "namespace" {
  description = "Namespace where Ory is deployed."
  value       = var.namespace
}

output "hydra_external_url" {
  description = "External (browser-facing) URL for Hydra. Use this as the OIDC issuer in Materialize."
  value       = local.hydra_external_url
}

output "kratos_external_url" {
  description = "External (browser-facing) URL for Kratos public API."
  value       = local.kratos_external_url
}

output "ui_external_url" {
  description = "External (browser-facing) URL for the Ory selfservice UI."
  value       = local.ui_external_url
}

output "polis_external_url" {
  description = "External (browser-facing) URL for Polis. Null when enable_polis is false."
  value       = local.polis_external_url
}

output "polis_admin_api_keys" {
  description = "API key for Polis admin APIs (generated or supplied). Null when enable_polis is false."
  value       = local.wire_polis ? module.ory_polis[0].admin_api_keys : null
  sensitive   = true
}

output "polis_db_encryption_key" {
  description = "Symmetric key used by Polis to encrypt sensitive fields at rest. Persist across applies, rotating invalidates existing records. Null when enable_polis is false."
  value       = local.wire_polis ? module.ory_polis[0].db_encryption_key : null
  sensitive   = true
}

output "hydra_secrets_system" {
  description = "Hydra system secret (generated or supplied). Persist in a durable store: a Hydra database restore needs this exact value to decrypt."
  value       = module.ory_hydra.secrets_system
  sensitive   = true
}

output "hydra_secrets_cookie" {
  description = "Hydra cookie secret (generated or supplied)."
  value       = module.ory_hydra.secrets_cookie
  sensitive   = true
}

output "kratos_secrets_default" {
  description = "Kratos default secret (generated or supplied)."
  value       = module.ory_kratos.secrets_default
  sensitive   = true
}

output "kratos_secrets_cookie" {
  description = "Kratos cookie secret (generated or supplied)."
  value       = module.ory_kratos.secrets_cookie
  sensitive   = true
}

output "kratos_secrets_cipher" {
  description = "Kratos cipher secret (generated or supplied). Persist in a durable store: a Kratos database restore needs this exact value to decrypt identity fields."
  value       = module.ory_kratos.secrets_cipher
  sensitive   = true
}

output "oauth2_client_secret_name" {
  description = "Name of the Secret that holds the Hydra-Maester-generated OAuth2 client credentials. Null when materialize_namespace is not set."
  value       = local.wire_materialize ? var.oauth2_client_name : null
}

output "oauth2_client_secret_namespace" {
  description = "Namespace of the OAuth2 client credentials Secret. Null when materialize_namespace is not set."
  value       = local.wire_materialize ? var.namespace : null
}

output "oauth2_client_id" {
  description = "Hydra-Maester-generated OAuth2 client ID for Materialize. Null when materialize_namespace is not set, or when the secret has not yet been populated by Hydra Maester (which can happen on a refresh that runs before Maester reconciles)."
  value       = local.wire_materialize ? try(data.kubernetes_secret_v1.oauth2_client[0].data["CLIENT_ID"], null) : null
  sensitive   = true
}

output "oel_registry_secret_name" {
  description = "Name of the dockerconfigjson Secret holding OEL registry credentials, in the Ory namespace."
  value       = kubernetes_secret.ory_oel_registry.metadata[0].name
}

output "lb_addresses" {
  description = "Ingress addresses of the LoadBalancer services this module owns. Map keyed by hostname role (hydra, kratos, ui, polis); values are objects with ip and hostname keys (GCP and Azure populate ip, AWS populates hostname). Use these to create the DNS records the browser-facing hostnames point at. Polis entry is null when disabled."
  value = {
    hydra  = try({ ip = kubernetes_service_v1.ory_lb["hydra-public-lb"].status[0].load_balancer[0].ingress[0].ip, hostname = kubernetes_service_v1.ory_lb["hydra-public-lb"].status[0].load_balancer[0].ingress[0].hostname }, null)
    kratos = try({ ip = kubernetes_service_v1.ory_lb["kratos-public-lb"].status[0].load_balancer[0].ingress[0].ip, hostname = kubernetes_service_v1.ory_lb["kratos-public-lb"].status[0].load_balancer[0].ingress[0].hostname }, null)
    ui     = var.deploy_selfservice_ui ? try({ ip = kubernetes_service_v1.ory_lb["ory-selfservice-ui-lb"].status[0].load_balancer[0].ingress[0].ip, hostname = kubernetes_service_v1.ory_lb["ory-selfservice-ui-lb"].status[0].load_balancer[0].ingress[0].hostname }, null) : null
    polis  = local.wire_polis ? try({ ip = kubernetes_service_v1.ory_lb["polis-public-lb"].status[0].load_balancer[0].ingress[0].ip, hostname = kubernetes_service_v1.ory_lb["polis-public-lb"].status[0].load_balancer[0].ingress[0].hostname }, null) : null
  }
}

output "kratos_namespace" {
  description = "Namespace of the Kratos deployment (same as namespace; kept for parity with submodule outputs)."
  value       = module.ory_kratos.namespace
}

output "hydra_namespace" {
  description = "Namespace of the Hydra deployment (same as namespace; kept for parity with submodule outputs)."
  value       = module.ory_hydra.namespace
}

output "ui_namespace" {
  description = "Namespace of the selfservice UI deployment (same as namespace; kept for parity with submodule outputs). Null when deploy_selfservice_ui is false."
  value       = var.deploy_selfservice_ui ? module.ory_selfservice_ui[0].namespace : null
}
