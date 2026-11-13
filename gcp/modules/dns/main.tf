locals {
  zone_project_id = coalesce(var.zone_project_id, var.project_id)
  zone_domain     = trimsuffix(data.google_dns_managed_zone.this.dns_name, ".")
  stem_domain     = var.stem_domain != null ? lower(trimsuffix(var.stem_domain, ".")) : local.zone_domain

  fqdns = {
    for key, entry in var.subdomains :
    key => coalesce(entry.subdomain, key) == "@" ? local.stem_domain : "${coalesce(entry.subdomain, key)}.${local.stem_domain}"
  }

  records = {
    for key, entry in var.subdomains : key => merge(entry, { fqdn = local.fqdns[key] }) if entry.create
  }

  cert_manager_dns01 = var.cert_manager_dns01 != null
}

# The zone is looked up, never managed: records are added to a zone that
# already exists, and nothing here can delete it.
data "google_dns_managed_zone" "this" {
  project = local.zone_project_id
  name    = var.zone_name

  lifecycle {
    postcondition {
      condition = (
        var.stem_domain == null ||
        lower(trimsuffix(var.stem_domain, ".")) == trimsuffix(self.dns_name, ".") ||
        endswith(lower(trimsuffix(var.stem_domain, ".")), ".${trimsuffix(self.dns_name, ".")}")
      )
      error_message = "stem_domain must be the managed zone's domain or a name inside it."
    }
  }
}

resource "google_dns_record_set" "subdomains" {
  for_each = local.records

  project      = local.zone_project_id
  managed_zone = var.zone_name
  name         = "${each.value.fqdn}."
  type         = each.value.type
  ttl          = each.value.ttl
  # Cloud DNS takes a CNAME target as an absolute name.
  rrdatas = each.value.type == "CNAME" ? [for target in each.value.records : endswith(target, ".") ? target : "${target}."] : each.value.records

  lifecycle {
    precondition {
      condition     = !(each.value.type == "CNAME" && each.value.fqdn == local.zone_domain)
      error_message = "${each.key}: a CNAME cannot sit at the zone's apex, ${local.zone_domain}."
    }
  }
}

# cert-manager's DNS-01 identity: a Google service account that may change
# records in this managed zone only, which cert-manager's Kubernetes service
# account impersonates through Workload Identity.
resource "google_service_account" "cert_manager" {
  count = local.cert_manager_dns01 ? 1 : 0

  project      = var.project_id
  account_id   = "${var.prefix}-cert-manager"
  display_name = "cert-manager ACME DNS-01 solver for ${var.zone_name}"

  lifecycle {
    precondition {
      condition     = length("${var.prefix}-cert-manager") <= 30
      error_message = "prefix must be at most 17 characters, so that the service account id ${var.prefix}-cert-manager fits GCP's 30-character limit."
    }
  }
}

resource "google_dns_managed_zone_iam_member" "cert_manager" {
  count = local.cert_manager_dns01 ? 1 : 0

  project      = local.zone_project_id
  managed_zone = var.zone_name
  role         = "roles/dns.admin"
  member       = "serviceAccount:${google_service_account.cert_manager[0].email}"
}

resource "google_service_account_iam_member" "cert_manager_workload_identity" {
  count = local.cert_manager_dns01 ? 1 : 0

  service_account_id = google_service_account.cert_manager[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.cert_manager_dns01.namespace}/${var.cert_manager_dns01.service_account_name}]"
}
