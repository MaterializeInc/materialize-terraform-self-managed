output "zone_domain" {
  description = "DNS name of the zone."
  value       = local.zone_domain
}

output "stem_domain" {
  description = "Domain the subdomains are created under."
  value       = local.stem_domain
}

output "fqdns" {
  description = "Fully qualified name of each entry in subdomains, keyed like subdomains, whether or not the module created its record."
  value       = local.fqdns
}

output "cert_manager_service_account_annotations" {
  description = "Annotations for cert-manager's Kubernetes service account, for the cert-manager module's service_account_annotations. The solver names the managed identity by client ID, so this is always empty; it matches the AWS and GCP dns modules."
  value       = {}
}

output "cert_manager_pod_labels" {
  description = "Labels for cert-manager's controller pods that opt them into Azure Workload Identity, for the cert-manager module's pod_labels. Empty when cert_manager_dns01 is null."
  value       = local.cert_manager_dns01 ? { "azure.workload.identity/use" = "true" } : {}
}

output "acme_dns01_solver" {
  description = "cert-manager ACME solver that answers DNS-01 challenges for stem_domain and its subdomains in this zone, for an element of the letsencrypt-cluster-issuer module's solvers. Null when cert_manager_dns01 is null."
  value = local.cert_manager_dns01 ? {
    selector = {
      dnsZones = [local.stem_domain]
    }
    dns01 = {
      azureDNS = {
        subscriptionID    = local.zone_subscription_id
        resourceGroupName = var.zone_resource_group_name
        hostedZoneName    = data.azurerm_dns_zone.this.name
        environment       = var.cert_manager_dns01.environment
        managedIdentity = {
          clientID = azurerm_user_assigned_identity.cert_manager[0].client_id
        }
      }
    }
  } : null
}
