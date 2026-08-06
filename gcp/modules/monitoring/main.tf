# Deploys the `materialize-monitoring` observability stack on GKE: Grafana
# dashboards, Prometheus-compatible metrics via Thanos, logs via Loki, and the
# Alloy collection pipeline.
#
# This module owns the GCP side — one GCS bucket per backend, a Google service
# account per backend, and the Workload Identity bindings that let the in-cluster
# service accounts impersonate them — and delegates everything inside the cluster
# to the cloud-agnostic module that ships alongside the chart in the
# `materialize-monitoring` repository. Nothing here names a Helm value path; that
# knowledge lives next to the chart, so a chart change and its Terraform
# consequence land together.
#
# Replaces the previous `kubernetes/modules/prometheus` and
# `kubernetes/modules/grafana`, which vendored a point-in-time dashboard copy and
# a legacy scrape config, collected metrics only, and ran a single Prometheus on
# a ReadWriteOnce volume with 15 days of retention.
#
# Operational notes:
#
#   * Workload Identity must be enabled on the cluster (`workload_pool` set on
#     the GKE cluster). Without it the bindings below exist but the pods still
#     fall back to the node service account.
#   * The `monitoring` namespace is created by the operator module in the
#     supported topology, so `create_namespace` defaults to false. Keep a
#     `depends_on` for the operator or the release can race the namespace.
#   * The operator module also installs metrics-server, which the Materialize
#     Console depends on for cluster metrics. If you disable it there, set
#     `install_metrics_server = true` here in the same change.
#   * Bucket lifecycle rules are off by default. Loki and Thanos both enforce
#     their own retention, and Thanos keeps blocks per downsampling resolution
#     (raw / 5m / 1h) — a bucket rule deleting sooner removes blocks the
#     compactor still references. Use them only as a backstop above that.
#   * Grafana is ClusterIP today (the chart exposes no ingress values yet), so
#     `grafana_url` is in-cluster: reach it with
#     `kubectl -n monitoring port-forward svc/grafana 3000:80` and
#     `terraform output -raw grafana_admin_password`.
#   * `node_selector` reaches every centralized workload but deliberately not
#     the Alloy agent DaemonSet, which must run on every node to collect from
#     it. `tolerations` do reach the agent, since they widen rather than narrow
#     where a pod may run.
#   * GKE does not expose the full cAdvisor and kube-state-metrics surface, so a
#     few percentage-based dashboard panels stay empty. That is a platform
#     limitation, not a misconfiguration.
#
# One bucket per backend rather than one shared with prefixes: Loki and Thanos
# want different lifecycle rules, IAM scoping is tighter, and Loki's
# `bucketNames` are bucket names rather than prefixes.

locals {
  # The chart renders deterministic ServiceAccount names, and the Workload
  # Identity members below have to match them exactly. The monitoring module
  # emits the resolved subjects as an output; these are the same names, needed
  # here before that module exists — passing them the other way would close a
  # dependency cycle.
  service_accounts = {
    loki   = "loki"
    thanos = "thanos-thanos"
  }

  # Not in the map above: the gateway binds to Cloud Monitoring, not a bucket.
  gateway_service_account = "alloy-gateway"

  buckets = {
    loki = {
      name           = "${var.prefix}-mzmon-logs-${var.project_id}"
      retention_days = var.logs_retention_days
    }
    thanos = {
      name           = "${var.prefix}-mzmon-metrics-${var.project_id}"
      retention_days = var.metrics_retention_days
    }
  }
}

# ==============================================================================
# Buckets
# ==============================================================================

resource "google_storage_bucket" "telemetry" {
  for_each = local.buckets

  name          = each.value.name
  location      = var.region
  project       = var.project_id
  force_destroy = var.bucket_force_destroy

  # Required for IAM-only access; both backends authenticate as a service
  # account, never with per-object ACLs.
  uniform_bucket_level_access = true

  versioning {
    enabled = var.enable_bucket_versioning
  }

  # Retention here is a backstop, not the primary control — see the header.
  dynamic "lifecycle_rule" {
    for_each = each.value.retention_days == null ? [] : [each.value.retention_days]
    content {
      action {
        type = "Delete"
      }
      condition {
        age = lifecycle_rule.value
      }
    }
  }

  # Versioning keeps a copy of every deleted object; without this the bucket
  # grows even as the compactor deletes.
  dynamic "lifecycle_rule" {
    for_each = var.enable_bucket_versioning ? [1] : []
    content {
      action {
        type = "Delete"
      }
      condition {
        days_since_noncurrent_time = 7
      }
    }
  }

  # Abandoned resumable uploads otherwise accumulate silently.
  lifecycle_rule {
    action {
      type = "AbortIncompleteMultipartUpload"
    }
    condition {
      age = 7
    }
  }

  labels = var.labels
}

# ==============================================================================
# Workload Identity
# ==============================================================================

resource "google_service_account" "telemetry" {
  for_each = local.service_accounts

  # account_id is capped at 30 characters, so the prefix is truncated rather
  # than allowed to overflow into an apply-time error.
  account_id   = substr("${var.prefix}-mzmon-${each.key}", 0, 30)
  display_name = "materialize-monitoring ${each.key}"
  project      = var.project_id
}

# Scoped to the one bucket that backend owns. objectAdmin rather than admin:
# both backends read, write, and delete objects, but neither needs to
# administer the bucket itself.
resource "google_storage_bucket_iam_member" "telemetry" {
  for_each = local.service_accounts

  bucket = google_storage_bucket.telemetry[each.key].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.telemetry[each.key].email}"
}

# Lets the in-cluster ServiceAccount impersonate the Google service account.
resource "google_service_account_iam_member" "workload_identity" {
  for_each = local.service_accounts

  service_account_id = google_service_account.telemetry[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${each.value}]"
}

# ==============================================================================
# Google Cloud Monitoring
# ==============================================================================
# Separate from the loop above: the gateway writes metrics, not objects, so it
# gets a project-level role and no bucket.

resource "google_service_account" "gateway" {
  count = var.enable_google_cloud_metrics ? 1 : 0

  account_id   = substr("${var.prefix}-mzmon-gateway", 0, 30)
  display_name = "materialize-monitoring gateway"
  project      = var.project_id
}

# metricWriter is write-only: it can publish time series and create metric
# descriptors, and cannot read anything back.
resource "google_project_iam_member" "gateway_metric_writer" {
  count = var.enable_google_cloud_metrics ? 1 : 0

  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gateway[0].email}"
}

resource "google_service_account_iam_member" "gateway_workload_identity" {
  count = var.enable_google_cloud_metrics ? 1 : 0

  service_account_id = google_service_account.gateway[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${local.gateway_service_account}]"
}

# ==============================================================================
# The stack
# ==============================================================================

module "monitoring" {
  # Pinned to a released tag. The module and the chart it installs are one
  # release, and the module reads its chart version out of the chart beside it —
  # so this ref alone names the chart version, with nothing to keep in sync.
  #
  # Developing against an unreleased module: point this at a local checkout
  # (`../../../../materialize-monitoring/terraform/modules/materialize-monitoring`)
  # for the duration. It must stay a *relative* path — an absolute one makes
  # Terraform copy the module without the chart directory beside it, and the
  # sizing profiles stop resolving.
  #
  # The `/` in the tag name is why this module floors at Terraform 1.10. Before
  # that fix, Terraform truncated the ref at the first slash and treated the rest
  # as a subdirectory, failing the clone with `pathspec 'materialize-monitoring'
  # did not match` (hashicorp/terraform#35552). See versions.tf.
  source = "github.com/MaterializeInc/materialize-monitoring//terraform/modules/materialize-monitoring?ref=materialize-monitoring/v0.12.0"

  namespace        = var.namespace
  create_namespace = var.create_namespace

  chart_version = var.chart_version

  sizing        = var.sizing
  node_selector = var.node_selector
  tolerations   = var.tolerations
  storage_class = var.storage_class

  materialize_instance_namespace = var.materialize_instance_namespace
  materialize_operator_namespace = var.materialize_operator_namespace
  install_metrics_server         = var.install_metrics_server

  grafana_admin_password = var.grafana_admin_password

  object_storage = {
    cloud         = "gcp"
    loki_bucket   = google_storage_bucket.telemetry["loki"].name
    thanos_bucket = google_storage_bucket.telemetry["thanos"].name

    loki_service_account_annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.telemetry["loki"].email
    }
    thanos_service_account_annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.telemetry["thanos"].email
    }
    # Only set when Cloud Monitoring is on; the gateway needs no bucket access.
    gateway_service_account_annotations = var.enable_google_cloud_metrics ? {
      "iam.gke.io/gcp-service-account" = google_service_account.gateway[0].email
    } : {}
  }

  google_cloud_metrics = var.enable_google_cloud_metrics ? {
    min_importance = var.google_cloud_metrics_min_importance
    prefix         = var.google_cloud_metrics_prefix
  } : null

  additional_values = var.additional_values

  depends_on = [
    google_storage_bucket_iam_member.telemetry,
    google_service_account_iam_member.workload_identity,
    google_project_iam_member.gateway_metric_writer,
    google_service_account_iam_member.gateway_workload_identity,
  ]
}
