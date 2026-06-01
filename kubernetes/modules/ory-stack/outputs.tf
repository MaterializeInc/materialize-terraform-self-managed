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

output "console_https_service_name" {
  description = "Name of the Materialize console HTTPS LoadBalancer Service. Null when materialize_namespace is not set."
  value       = local.wire_materialize ? kubernetes_service_v1.console_https_lb[0].metadata[0].name : null
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
  description = "Namespace of the selfservice UI deployment (same as namespace; kept for parity with submodule outputs)."
  value       = module.ory_selfservice_ui.namespace
}
