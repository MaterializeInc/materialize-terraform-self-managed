resource "google_service_account" "gke_sa" {
  project      = var.project_id
  account_id   = "${var.prefix}-gke-sa"
  display_name = "GKE Service Account for Materialize"
}

resource "google_service_account" "workload_identity_sa" {
  project      = var.project_id
  account_id   = "${var.prefix}-materialize-sa"
  display_name = "Materialize Workload Identity Service Account"
}

resource "google_container_cluster" "primary" {
  provider = google

  deletion_protection = false

  depends_on = [
    google_service_account.gke_sa,
    google_service_account.workload_identity_sa,
  ]

  name     = "${var.prefix}-gke"
  location = var.region
  project  = var.project_id

  networking_mode = var.networking_mode
  network         = var.network_name
  subnetwork      = var.subnet_name

  remove_default_node_pool = true
  initial_node_count       = 1

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = var.cluster_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  release_channel {
    channel = var.release_channel
  }

  addons_config {
    horizontal_pod_autoscaling {
      disabled = var.horizontal_pod_autoscaling_disabled
    }
    http_load_balancing {
      disabled = var.http_load_balancing_disabled
    }
    gce_persistent_disk_csi_driver_config {
      enabled = var.gce_persistent_disk_csi_driver_enabled
    }
  }
}

resource "google_service_account_iam_binding" "workload_identity" {
  depends_on = [
    google_service_account.workload_identity_sa,
    google_container_cluster.primary
  ]
  service_account_id = google_service_account.workload_identity_sa.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/orchestratord]"
  ]
}

# System nodepool for running critical system pods
resource "google_container_node_pool" "system_nodes" {
  provider = google

  name     = "${var.prefix}-system-nodepool"
  location = var.region
  cluster  = google_container_cluster.primary.name
  project  = var.project_id

  node_count = var.system_nodepool_node_count

  autoscaling {
    min_node_count = var.system_nodepool_min_nodes
    max_node_count = var.system_nodepool_max_nodes
  }

  network_config {
    enable_private_nodes = var.system_nodepool_enable_private_nodes
  }

  node_config {
    machine_type = var.system_nodepool_machine_type
    disk_size_gb = var.system_nodepool_disk_size_gb

    labels = {
      "workload" = "system"
    }

    taint {
      key    = "CriticalAddonsOnly"
      value  = ""
      effect = "NO_SCHEDULE"
    }

    service_account = google_service_account.gke_sa.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  lifecycle {
    create_before_destroy = true
    prevent_destroy       = false
  }

  depends_on = [google_container_cluster.primary]
}
