/**
 * # cloudflared connector (GCP)
 *
 * Runs Cloudflare Tunnel connectors (`cloudflared`) as a regional managed
 * instance group inside a VPC, so a tunnel created with
 * `cloudflare/modules/tunnel` can reach a Materialize environment's internal
 * load balancers.
 *
 * The VMs have no public IP and no inbound firewall rules: `cloudflared` only
 * dials out to Cloudflare, so the subnetwork needs outbound internet access
 * (for example Cloud NAT). The tunnel token is stored in Secret Manager and
 * read at boot by the VMs' service account, whose only grant is read access
 * to that secret.
 *
 * Requires the Secret Manager API (`secretmanager.googleapis.com`) in the
 * project.
 */

resource "google_service_account" "connector" {
  project      = var.project_id
  account_id   = "${var.name_prefix}-cfd"
  display_name = "cloudflared connector (${var.name_prefix})"
}

resource "google_secret_manager_secret" "tunnel_token" {
  project   = var.project_id
  secret_id = "${var.name_prefix}-cloudflared-tunnel-token"
  labels    = var.labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "tunnel_token" {
  secret      = google_secret_manager_secret.tunnel_token.id
  secret_data = var.tunnel_token
}

data "google_project" "this" {
  project_id = var.project_id
}

# A project binding conditioned on this one secret, rather than a binding on
# the secret itself: setting a secret's IAM policy needs Secret Manager admin,
# while project bindings need only the Project IAM Admin role the examples
# already require. The condition keeps the grant to this secret's versions.
resource "google_project_iam_member" "connector_secret_access" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = google_service_account.connector.member

  condition {
    title       = "${var.name_prefix}-cloudflared-tunnel-token"
    description = "Only the cloudflared tunnel token secret"
    expression  = "resource.name.startsWith(\"projects/${data.google_project.this.number}/secrets/${google_secret_manager_secret.tunnel_token.secret_id}/\")"
  }
}

locals {
  cloud_init = "#cloud-config\n${yamlencode({
    write_files = [
      {
        path        = "/var/lib/cloudflared/fetch-tunnel-token.sh"
        permissions = "0755"
        content     = file("${path.module}/scripts/fetch-tunnel-token.sh")
      },
      {
        path        = "/etc/systemd/system/cloudflared.service"
        permissions = "0644"
        content     = templatefile("${path.module}/templates/cloudflared.service.tftpl", { image = var.cloudflared_image })
      },
    ]
    runcmd = [
      "systemctl daemon-reload",
      "systemctl start cloudflared.service",
    ]
  })}"
}

resource "google_compute_instance_template" "connector" {
  project      = var.project_id
  name_prefix  = "${var.name_prefix}-cfd-"
  machine_type = var.machine_type
  region       = var.region
  labels       = var.labels

  disk {
    source_image = "projects/cos-cloud/global/images/family/cos-stable"
    auto_delete  = true
    boot         = true
    disk_size_gb = 10
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork
  }

  metadata = {
    user-data              = local.cloud_init
    block-project-ssh-keys = "true"
    # The secret version's name, not its value. A new version (a rotated
    # token) changes the template, which rolls the connectors.
    tunnel-token-secret = google_secret_manager_secret_version.tunnel_token.name
  }

  service_account {
    email = google_service_account.connector.email
    # IAM decides what the account can reach; it can read only the tunnel
    # token secret.
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot = true
  }

  lifecycle {
    create_before_destroy = true
  }

  # The VMs read the secret as they boot.
  depends_on = [google_project_iam_member.connector_secret_access]
}

resource "google_compute_region_instance_group_manager" "connector" {
  project            = var.project_id
  name               = "${var.name_prefix}-cfd"
  region             = var.region
  base_instance_name = "${var.name_prefix}-cfd"
  target_size        = var.replicas

  version {
    instance_template = google_compute_instance_template.connector.id
  }

  # Surge new connectors before removing old ones, so the tunnel keeps a
  # connection through template changes. A regional group needs a surge of at
  # least its zone count.
  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_surge_fixed       = 3
    max_unavailable_fixed = 0
  }
}
