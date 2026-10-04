# =============================================================================
# GCP Migration Configuration
# =============================================================================
# Accepts state migrated from the old monolithic GCP module (gcp-old/).
# Resources whose new modules would force recreation are defined inline:
#   - Networking: VPC, subnet, route, VPC peering
#   - GKE: cluster, service accounts, workload identity binding
#   - System node pool: from old GKE module
#   - Database: Cloud SQL instance, database, user
# Everything else uses the shared modules.
# =============================================================================

# =============================================================================
# Providers
# =============================================================================

provider "google" {
  project = var.project_id
  region  = var.region
  # No default_labels, as in the old module: they would add label diffs to
  # resources that never had labels. Labels are set per resource instead.
}

# Used by the nodepool module for autoscaled blue-green upgrade settings,
# which are not yet available in the GA google provider.
provider "google-beta" {
  project = var.project_id
  region  = var.region
}

data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.primary.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  }
}

# lazy_load (alekc/kubectl v2.4.0+) defers kubeconfig resolution until first use.
# Without it, plans fail with an empty REST config while cluster outputs are unknown.
# See https://registry.terraform.io/providers/alekc/kubectl/latest/docs#troubleshooting
provider "kubectl" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)

  load_config_file = false
  lazy_load        = true
}

# =============================================================================
# Locals
# =============================================================================

locals {
  # Matches the old module's common_labels; changing node pool labels rotates nodes.
  common_labels = merge(var.labels, {
    managed_by = "terraform"
    module     = "materialize"
  })

  # System node pool labels (matches old GKE module)
  system_node_labels = merge(
    local.common_labels,
    {
      "workload" = "system"
    }
  )

  # Backend URL construction (matches old module format)
  encoded_endpoint = urlencode("https://storage.googleapis.com")
  encoded_secret   = urlencode(module.storage.hmac_secret)

  metadata_backend_url = format(
    "postgres://%s:%s@%s:5432/%s?sslmode=disable",
    var.database_username,
    urlencode(var.database_password),
    google_sql_database_instance.materialize.private_ip_address,
    var.database_name
  )

  persist_backend_url = format(
    "s3://%s:%s@%s/materialize?endpoint=%s&region=%s",
    module.storage.hmac_access_id,
    local.encoded_secret,
    module.storage.bucket_name,
    local.encoded_endpoint,
    var.region
  )
}

# =============================================================================
# INLINE: Networking
# =============================================================================
# The new networking module wraps terraform-google-modules (different state
# paths, adds Cloud NAT), which would force recreation.
# =============================================================================

resource "google_compute_network" "vpc" {
  name                    = "${var.prefix}-network"
  auto_create_subnetworks = false
  project                 = var.project_id

  lifecycle {
    create_before_destroy = true
    prevent_destroy       = false
  }
}

resource "google_compute_route" "default_route" {
  name             = "${var.prefix}-default-route"
  project          = var.project_id
  network          = google_compute_network.vpc.name
  dest_range       = "0.0.0.0/0"
  priority         = 1000
  next_hop_gateway = "default-internet-gateway"

  depends_on = [google_compute_network.vpc]

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.prefix}-subnet"
  project       = var.project_id
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.subnet_cidr
  region        = var.region

  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
}

resource "google_compute_global_address" "private_ip_address" {
  provider      = google
  project       = var.project_id
  name          = "${var.prefix}-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_service_networking_connection" "private_vpc_connection" {
  provider                = google
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]

  lifecycle {
    create_before_destroy = true
  }

  deletion_policy = "ABANDON"
}

# =============================================================================
# INLINE: GKE Cluster & Service Accounts
# =============================================================================
# The new GKE module adds private_cluster_config, master_authorized_networks
# and L4 LB settings, which could update or recreate the cluster.
# =============================================================================

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

  # Matches old module: VPC_NATIVE, no private_cluster_config
  networking_mode = "VPC_NATIVE"
  network         = google_compute_network.vpc.name
  subnetwork      = google_compute_subnetwork.subnet.name

  remove_default_node_pool = true
  initial_node_count       = 1

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  release_channel {
    channel = "REGULAR"
  }

  addons_config {
    horizontal_pod_autoscaling {
      disabled = false
    }
    http_load_balancing {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }
}

# System node pool, from the old GKE module's google_container_node_pool.primary_nodes
resource "google_container_node_pool" "system" {
  provider = google

  name     = "${var.prefix}-system-node-pool"
  location = var.region
  cluster  = google_container_cluster.primary.name
  project  = var.project_id

  node_count = var.system_node_pool_node_count

  autoscaling {
    min_node_count = var.system_node_pool_min_nodes
    max_node_count = var.system_node_pool_max_nodes
  }

  node_config {
    machine_type = var.system_node_pool_machine_type
    disk_size_gb = var.system_node_pool_disk_size_gb

    labels = local.system_node_labels

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

# =============================================================================
# INLINE: Database (Cloud SQL)
# =============================================================================
# The new database module wraps terraform-google-modules/sql-db, which has
# different state paths.
# =============================================================================

resource "time_sleep" "wait_for_vpc" {
  depends_on = [google_service_networking_connection.private_vpc_connection]

  create_duration = var.database_vpc_wait_duration
}

resource "google_sql_database_instance" "materialize" {
  depends_on = [time_sleep.wait_for_vpc]

  name             = "${var.prefix}-pg"
  database_version = var.database_version
  region           = var.region
  project          = var.project_id

  timeouts {
    create = "75m"
    update = "45m"
    delete = "45m"
  }

  settings {
    tier = var.database_tier

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      backup_retention_settings {
        retained_backups = 7
      }
    }

    maintenance_window {
      day          = 7
      hour         = 3
      update_track = "stable"
    }

    user_labels = local.common_labels
  }

  deletion_protection = false
}

resource "google_sql_database" "materialize" {
  name     = var.database_name
  instance = google_sql_database_instance.materialize.name
  project  = var.project_id

  deletion_policy = "ABANDON"
}

resource "google_sql_user" "materialize" {
  name     = var.database_username
  instance = google_sql_database_instance.materialize.name
  password = var.database_password
  project  = var.project_id

  deletion_policy = "ABANDON"
}

# =============================================================================
# MODULE: Materialize Node Pool
# =============================================================================
# Same node pool as the old module, plus blue-green upgrade settings that
# apply in place.
# =============================================================================

module "materialize_nodepool" {
  source     = "../../modules/nodepool"
  depends_on = [google_container_cluster.primary]

  prefix                = "${var.prefix}-mz-swap"
  region                = var.region
  enable_private_nodes  = true
  cluster_name          = google_container_cluster.primary.name
  project_id            = var.project_id
  min_nodes             = var.materialize_node_pool_min_nodes
  max_nodes             = var.materialize_node_pool_max_nodes
  machine_type          = var.materialize_node_pool_machine_type
  disk_size_gb          = var.materialize_node_pool_disk_size_gb
  service_account_email = google_service_account.gke_sa.email
  labels                = local.common_labels

  swap_enabled    = true
  local_ssd_count = var.materialize_node_pool_local_ssd_count

  # Pin to old version to avoid unintended daemonset image upgrade
  disk_setup_image = "materialize/ephemeral-storage-setup-image:v0.4.0"

  # MIGRATION: the old "<prefix>-disk-setup" name (also the module default).
  # A different name replaces the 5 disk setup Kubernetes resources.
  disk_setup_name = "${var.prefix}-mz-swap-disk-setup"
}

# =============================================================================
# MODULE: Storage (GCS)
# =============================================================================
# Same resources and state paths as the old storage module.
# =============================================================================

module "storage" {
  source = "../../modules/storage"

  project_id      = var.project_id
  region          = var.region
  prefix          = var.prefix
  service_account = google_service_account.workload_identity_sa.email
  versioning      = var.storage_bucket_versioning
  version_ttl     = var.storage_bucket_version_ttl

  labels = local.common_labels
}

# =============================================================================
# MODULE: cert-manager
# =============================================================================
# Split from the old certificates module; namespace and helm release are moved.
# =============================================================================

module "cert_manager" {
  source = "../../../kubernetes/modules/cert-manager"

  chart_version = var.cert_manager_chart_version

  depends_on = [
    google_container_cluster.primary,
  ]
}

# =============================================================================
# MODULE: Self-Signed Cluster Issuer
# =============================================================================
# Split from the old certificates module. The manifests changed from
# kubernetes_manifest to kubectl_manifest, so the migration skips them and
# kubectl_manifest adopts the existing Kubernetes resources on apply.
# =============================================================================

module "self_signed_cluster_issuer" {
  count = var.use_self_signed_cluster_issuer ? 1 : 0

  source = "../../../kubernetes/modules/self-signed-cluster-issuer"

  name_prefix = var.prefix

  depends_on = [
    module.cert_manager,
  ]
}

# =============================================================================
# MODULE: Materialize Operator
# =============================================================================
# The old external module used count; auto-migrate.py drops the [0] index.
# =============================================================================

module "operator" {
  source = "../../modules/operator"

  # MIGRATION: name_prefix is the helm release name. Keep the old one
  # ("${namespace}-${environment}", by default "materialize-${prefix}") to avoid replacing it.
  # A replacement is usually harmless: the operator is a controller and instances keep running.
  name_prefix = "materialize-${var.prefix}"
  region      = var.region

  operator_version = var.operator_version

  # MIGRATION: the old module pinned environmentd to swap nodes; keep it to
  # avoid rescheduling pods.
  helm_values = merge(
    {
      environmentd = {
        nodeSelector = {
          "materialize.cloud/swap" = "true"
        }
      }
    },
    var.use_self_signed_cluster_issuer ? {
      tls = {
        defaultCertificateSpecs = {
          balancerdExternal = {
            dnsNames = [
              "balancerd",
            ]
            issuerRef = {
              name = "${var.prefix}-root-ca"
              kind = "ClusterIssuer"
            }
          }
          consoleExternal = {
            dnsNames = [
              "console",
            ]
            issuerRef = {
              name = "${var.prefix}-root-ca"
              kind = "ClusterIssuer"
            }
          }
          internal = {
            issuerRef = {
              name = "${var.prefix}-root-ca"
              kind = "ClusterIssuer"
            }
          }
        }
      }
    } : {}
  )

  depends_on = [
    google_container_cluster.primary,
    module.materialize_nodepool,
    google_sql_database_instance.materialize,
    module.storage,
    module.cert_manager,
  ]
}

# =============================================================================
# MODULE: Materialize Instance
# =============================================================================
# Namespace and backend secret move here from the old operator module. The
# instance manifest changed to kubectl_manifest, which adopts the existing
# Materialize resource without disruption.
# =============================================================================

module "materialize_instance" {
  source = "../../../kubernetes/modules/materialize-instance"

  instance_name      = var.materialize_instance_name
  instance_namespace = var.materialize_instance_namespace

  metadata_backend_url = local.metadata_backend_url
  persist_backend_url  = local.persist_backend_url

  license_key        = var.license_key
  authenticator_kind = var.authenticator_kind

  external_login_password_mz_system = var.external_login_password_mz_system

  environmentd_version = var.environmentd_version

  # Rollout configuration
  force_rollout   = var.force_rollout
  request_rollout = var.request_rollout

  service_account_annotations = {
    "iam.gke.io/gcp-service-account" = google_service_account.workload_identity_sa.email
  }

  issuer_ref = var.use_self_signed_cluster_issuer ? {
    name = "${var.prefix}-root-ca"
    kind = "ClusterIssuer"
  } : null

  depends_on = [
    google_container_cluster.primary,
    google_sql_database_instance.materialize,
    module.storage,
    module.self_signed_cluster_issuer,
    module.operator,
    module.materialize_nodepool,
  ]
}

# =============================================================================
# MODULE: Load Balancers
# =============================================================================
# The old module used for_each; auto-migrate.py drops the key. The firewall
# rules are new and are created on apply.
# =============================================================================

module "load_balancers" {
  source = "../../modules/load_balancers"

  project_id                 = var.project_id
  network_name               = google_compute_network.vpc.name
  prefix                     = var.prefix
  node_service_account_email = google_service_account.gke_sa.email
  internal                   = var.internal_load_balancer
  ingress_cidr_blocks        = var.ingress_cidr_blocks
  instance_name              = var.materialize_instance_name
  namespace                  = var.materialize_instance_namespace
  resource_id                = module.materialize_instance.instance_resource_id

  depends_on = [
    module.materialize_instance,
  ]
}

# =============================================================================
# CoreDNS (commented out)
# =============================================================================
# Not part of the old setup. Replaces kube-dns with zero-TTL caching;
# uncomment after migration if wanted.
#
# module "coredns" {
#   source                                      = "../../../kubernetes/modules/coredns"
#   create_coredns_service_account              = true
#   kubeconfig_data                             = local.kubeconfig_data
#   coredns_deployment_to_scale_down            = "kube-dns"
#   coredns_autoscaler_deployment_to_scale_down = "kube-dns-autoscaler"
#   depends_on = [
#     google_container_cluster.primary,
#   ]
# }
# =============================================================================
