data "google_dns_managed_zone" "zone" {
  project = var.project_id
  name    = var.dns_zone_name
}

resource "google_dns_record_set" "balancerd" {
  project      = var.project_id
  managed_zone = data.google_dns_managed_zone.zone.name
  name         = "${var.balancerd_hostname}."
  type         = "A"
  ttl          = var.dns_ttl
  rrdatas      = [var.balancerd_ip]
}

resource "google_dns_record_set" "console" {
  project      = var.project_id
  managed_zone = data.google_dns_managed_zone.zone.name
  name         = "${var.console_hostname}."
  type         = "A"
  ttl          = var.dns_ttl
  rrdatas      = [var.console_ip]
}
