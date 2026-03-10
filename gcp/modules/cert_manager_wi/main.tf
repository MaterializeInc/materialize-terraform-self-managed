resource "google_service_account" "cert_manager" {
  project      = var.project_id
  account_id   = var.service_account_name
  display_name = "cert-manager DNS01 solver"
}

data "google_dns_managed_zone" "zone" {
  project = var.project_id
  name    = var.dns_zone_name
}

resource "google_dns_managed_zone_iam_member" "cert_manager_dns_admin" {
  project      = var.project_id
  managed_zone = data.google_dns_managed_zone.zone.name
  role         = "roles/dns.admin"
  member       = "serviceAccount:${google_service_account.cert_manager.email}"
}

resource "google_service_account_iam_member" "cert_manager_workload_identity" {
  service_account_id = google_service_account.cert_manager.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.cert_manager_namespace}/cert-manager]"
}
