#TODO: Currently all the nodepools share this service account. Should we create separate service accounts for different nodepools at nodepool level?
#  Doing this will allow more flexibility in terms of permissions/firewalls for different nodepools.
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

locals {
  # Deduplicate CIDR blocks by converting to a map keyed by cidr_block
  # This ensures each CIDR block appears only once (set-like behavior)
  # If duplicates exist, the last occurrence is kept
  unique_k8s_apiserver_authorized_networks = {
    for network in var.k8s_apiserver_authorized_networks :
    network.cidr_block => network
  }

  # This range only needs to be the GKE control plane,
  # but the documented way of getting the CIDR seems to return null.
  master_ipv4_cidr_block                = google_container_cluster.primary.private_cluster_config[0].master_ipv4_cidr_block
  conversion_webhook_rule_source_ranges = (local.master_ipv4_cidr_block != "" && local.master_ipv4_cidr_block != null) ? local.master_ipv4_cidr_block : "0.0.0.0/0"
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

  # Zones where nodes are created. For regional clusters, controls which zones
  # host nodes (the control plane is already replicated across zones).
  node_locations = var.node_locations

  networking_mode = var.networking_mode
  network         = var.network_name
  subnetwork      = var.subnet_name

  # ADVANCED_DATAPATH (Dataplane V2) uses eBPF-based networking with built-in
  # NetworkPolicy support; standard Kubernetes NetworkPolicy is automatically
  # enforced. The legacy datapath ignores NetworkPolicy resources entirely.
  # Cannot be changed on an existing cluster without rebuilding it.
  # Reference: https://cloud.google.com/kubernetes-engine/docs/how-to/dataplane-v2
  datapath_provider = var.datapath_provider

  remove_default_node_pool = true
  initial_node_count       = 1

  resource_labels = var.labels

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = var.cluster_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  # Enable private cluster with both private and public endpoint access
  # ref : https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/container_cluster#private_cluster_config-1
  private_cluster_config {
    # enables private cluster feature,creating a private endpoint on cluster
    enable_private_nodes = true
    # when enable_private_endpoint is true, it disables the access through public endpoint, hence this is set to false.
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  # Allow access to the cluster endpoint from specific IP ranges
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = local.unique_k8s_apiserver_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
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
    dns_cache_config {
      enabled = var.enable_node_local_dns
    }
  }

  # https://docs.cloud.google.com/kubernetes-engine/docs/how-to/user-managed-firewall-rules#disable-in-new-cluster
  disable_l4_lb_firewall_reconciliation = true
  enable_l4_ilb_subsetting              = true

  # Publish upgrade notifications to Pub/Sub so that orchestratord can react
  # to node pool upgrades (see the operator module's
  # enable_node_upgrade_rollout_trigger).
  dynamic "notification_config" {
    for_each = var.enable_upgrade_notifications ? [1] : []
    content {
      pubsub {
        enabled = true
        topic   = google_pubsub_topic.upgrade_notifications[0].id
        filter {
          event_type = ["UPGRADE_EVENT"]
        }
      }
    }
  }
}

resource "google_pubsub_topic" "upgrade_notifications" {
  count = var.enable_upgrade_notifications ? 1 : 0

  project = var.project_id
  name    = "${var.prefix}-gke-upgrade-notifications"
  labels  = var.labels
}

resource "google_pubsub_subscription" "orchestratord_upgrade_notifications" {
  count = var.enable_upgrade_notifications ? 1 : 0

  project = var.project_id
  name    = "${var.prefix}-orchestratord-upgrade-notifications"
  topic   = google_pubsub_topic.upgrade_notifications[0].id
  labels  = var.labels

  # Notifications older than this are only useful for arming faster than
  # orchestratord's periodic poll of the GKE API, which also catches any
  # upgrades whose notifications expired here.
  message_retention_duration = "86400s"

  # Never expire the subscription due to inactivity: upgrades can be rare.
  expiration_policy {
    ttl = ""
  }
}

resource "google_pubsub_subscription_iam_member" "orchestratord_upgrade_notifications_subscriber" {
  count = var.enable_upgrade_notifications ? 1 : 0

  project      = var.project_id
  subscription = google_pubsub_subscription.orchestratord_upgrade_notifications[0].name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.workload_identity_sa.email}"
}

# Lets orchestratord read node pool state (blue-green upgrade phase) to
# decide when it is safe to trigger rollouts.
resource "google_project_iam_member" "orchestratord_cluster_viewer" {
  count = var.enable_upgrade_notifications ? 1 : 0

  project = var.project_id
  role    = "roles/container.clusterViewer"
  member  = "serviceAccount:${google_service_account.workload_identity_sa.email}"
}

# Firewall rule to allow traffic to nodes on port 8001 for conversion webhooks.
# In private clusters, the GKE control plane needs to reach node ports for
# webhook callbacks (e.g., CRD conversion webhooks).
resource "google_compute_firewall" "conversion_webhook" {
  project     = var.project_id
  name        = "${var.prefix}-gke-conversion-webhook"
  network     = var.network_name
  description = "Allow traffic to nodes on port 8001 for conversion webhooks"
  direction   = "INGRESS"
  allow {
    protocol = "tcp"
    ports    = ["8001"]
  }
  source_ranges           = [local.conversion_webhook_rule_source_ranges]
  target_service_accounts = [google_service_account.gke_sa.email]
}

resource "google_service_account_iam_binding" "workload_identity" {
  depends_on = [
    google_service_account.workload_identity_sa,
    google_container_cluster.primary
  ]
  service_account_id = google_service_account.workload_identity_sa.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${var.orchestratord_service_account_name}]"
  ]
}
