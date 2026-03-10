resource "google_compute_address" "balancerd" {
  project      = var.project_id
  name         = "${var.prefix}-balancerd-ip"
  region       = var.region
  address_type = "EXTERNAL"
}

resource "google_compute_address" "console" {
  project      = var.project_id
  name         = "${var.prefix}-console-ip"
  region       = var.region
  address_type = "EXTERNAL"
}
