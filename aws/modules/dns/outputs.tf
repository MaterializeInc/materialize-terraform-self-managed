output "zone_domain" {
  description = "DNS name of the hosted zone, without the trailing dot."
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
  description = "Annotations for cert-manager's Kubernetes service account that give it the DNS-01 identity, for the cert-manager module's service_account_annotations. Empty when cert_manager_dns01 is null."
  value       = local.cert_manager_dns01 ? { "eks.amazonaws.com/role-arn" = aws_iam_role.cert_manager[0].arn } : {}
}

output "cert_manager_pod_labels" {
  description = "Labels for cert-manager's controller pods, for the cert-manager module's pod_labels. IRSA needs none, so this is always empty; it matches the GCP and Azure dns modules."
  value       = {}
}

output "acme_dns01_solver" {
  description = "cert-manager ACME solver that answers DNS-01 challenges for stem_domain and its subdomains in this hosted zone, for an element of the letsencrypt-cluster-issuer module's solvers. Null when cert_manager_dns01 is null."
  value = local.cert_manager_dns01 ? {
    selector = {
      dnsZones = [local.stem_domain]
    }
    dns01 = {
      route53 = {
        region       = data.aws_region.current.region
        hostedZoneID = var.zone_id
      }
    }
  } : null
}
