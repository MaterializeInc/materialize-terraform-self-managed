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
#   * Bucket *retention* is off by default, but housekeeping always runs.
#     Deleting noncurrent versions is unconditional, because nothing else ever
#     reclaims them. Soft delete is explicitly disabled for the same reason it
#     exists — it bills as stored bytes and duplicates the versioning we
#     already configure. The multipart-abort rule is a safety net for the
#     S3-compatible path only; see the comment on the rule itself. Only
#     `logs_retention_days` / `metrics_retention_days` are opt-in: Loki and
#     Thanos both enforce their own retention, and Thanos keeps blocks per
#     downsampling resolution (raw / 5m / 1h), so a bucket rule deleting sooner
#     removes blocks the compactor still references.
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

  # Off, not defaulted. New buckets get a 7-day soft-delete retention that is
  # billed as stored bytes, so with versioning and the noncurrent rule below we
  # would pay twice for everything the compactors delete — once as a noncurrent
  # version and again as a soft-deleted object. Versioning is the recovery
  # mechanism we actually configure; this one is invisible and duplicates it.
  soft_delete_policy {
    retention_duration_seconds = 0
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
  #
  # Unconditional rather than gated on `enable_bucket_versioning`: turning
  # versioning off does not remove the versions already written, so gating this
  # would strand them in the same apply that stops new ones. On a bucket that
  # was never versioned the condition simply never matches.
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      days_since_noncurrent_time = 7
    }
  }

  # This covers XML API multipart uploads, which is *not* the same thing as
  # resumable uploads — only the former strands billable parts that nothing
  # reclaims. Loki and Thanos talking to GCS natively use the Go client, which
  # does resumable uploads, and those session URIs expire on their own after a
  # week.
  #
  # So this rule does nothing on the default configuration, and is kept as a
  # safety net for the case where something is pointed at these buckets through
  # the S3-compatible XML API instead. `AbortIncompleteMultipartUpload` is one
  # of the three GCS lifecycle actions, alongside `Delete` and
  # `SetStorageClass`, and `age` is one of the three conditions it accepts.
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

  # No truncation here on purpose: `var.prefix` is validated at 17 characters,
  # which is exactly what keeps the longest of these (`-mzmon-thanos`) inside
  # the 30-character account_id limit.
  account_id   = "${var.prefix}-mzmon-${each.key}"
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
  #
  # v0.13.0 is where `grafana_database_*` and the chart's `grafana.ingress` /
  # `grafana.service` values land. This branch does not plan against v0.12.0.
  source = "github.com/MaterializeInc/materialize-monitoring//terraform/modules/materialize-monitoring?ref=materialize-monitoring/v0.15.0"

  namespace        = var.namespace
  create_namespace = var.create_namespace

  chart_version = var.chart_version

  # Null on any of these means "use the monitoring module's own default": each
  # is declared `nullable = false` with a default there, and Terraform
  # substitutes the default when a caller passes null. None of the three is
  # reachable through `additional_values`, so without forwarding them a mirrored
  # registry or a cluster that already owns the CRDs has no way through.
  chart_registry         = var.chart_registry
  enable_monitoring_crds = var.enable_monitoring_crds
  install_timeout        = var.install_timeout

  sizing        = var.sizing
  node_selector = var.node_selector
  tolerations   = var.tolerations
  storage_class = var.storage_class

  materialize_instance_namespace = var.materialize_instance_namespace
  materialize_operator_namespace = var.materialize_operator_namespace
  install_metrics_server         = var.install_metrics_server

  grafana_admin_password = var.grafana_admin_password

  # Explicit rather than inferred from host/password: both are computed here — an
  # instance endpoint and a generated password — so the module cannot decide
  # whether they exist at plan time. These two conditions are plan-known.
  grafana_database_enabled                = local.create_grafana_database || var.grafana_database_host != null
  grafana_database_manage_password_secret = local.create_grafana_database || var.grafana_database_password != null

  grafana_database_host     = local.grafana_database_host
  grafana_database_port     = local.grafana_database_port
  grafana_database_name     = var.grafana_database_name
  grafana_database_user     = var.grafana_database_user
  grafana_database_password = local.grafana_database_effective_password
  grafana_database_ssl_mode = var.grafana_database_ssl_mode

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

  # Load-balancer values ahead of the caller's, so `additional_values` still
  # overrides anything computed here.
  additional_values = concat(local.grafana_load_balancer_values, var.additional_values)

  depends_on = [
    google_storage_bucket_iam_member.telemetry,
    google_service_account_iam_member.workload_identity,
    google_project_iam_member.gateway_metric_writer,
    google_service_account_iam_member.gateway_workload_identity,
  ]
}

# ==============================================================================
# Grafana state database
# ==============================================================================
# Reuses this repo's own `database` module rather than an inline
# `google_sql_database_instance`, so Grafana's instance gets the same backup,
# maintenance, and private-networking opinions the Materialize database has.

resource "random_password" "grafana_database" {
  count = var.grafana_database != null && var.grafana_database_password == null ? 1 : 0

  length = 32
  # Cloud SQL accepts more, but Grafana reads this out of a mounted file and
  # operators paste it into psql. Alphanumeric avoids both quoting questions.
  special = false
}

module "grafana_database" {
  count  = var.grafana_database == null ? 0 : 1
  source = "../database"

  project_id = var.project_id
  region     = var.region
  prefix     = "${var.prefix}-mzmon-grafana"
  network_id = var.grafana_database.network_id

  tier       = var.grafana_database.tier
  db_version = var.grafana_database.db_version
  edition    = var.grafana_database.edition
  disk_size  = var.grafana_database.disk_size

  backup_enabled                 = var.grafana_database.backup_enabled
  point_in_time_recovery_enabled = var.grafana_database.point_in_time_recovery_enabled

  databases = [{ name = var.grafana_database_name }]
  users     = [{ name = var.grafana_database_user, password = local.grafana_database_password }]

  labels = var.labels
}

locals {
  create_grafana_database = var.grafana_database != null

  # A caller-supplied password wins in both modes; the random one only fills the
  # gap when this module creates the instance and was given none.
  #
  # Not `coalesce`: it errors when every argument is null, which is the default
  # install — no database and no password — so it failed the plan on the one path
  # that has nothing to decide. Null here means "no password", which is what the
  # module's own gates are for.
  grafana_database_password = (
    var.grafana_database_password != null
    ? var.grafana_database_password
    : one(random_password.grafana_database[*].result)
  )

  # Cloud SQL private IP. `host` on an external instance may be a name.
  grafana_database_host = local.create_grafana_database ? (
    module.grafana_database[0].private_ip
  ) : var.grafana_database_host

  grafana_database_port = local.create_grafana_database ? 5432 : var.grafana_database_port

  grafana_database_effective_password = (
    local.create_grafana_database ? local.grafana_database_password : var.grafana_database_password
  )
}

# ==============================================================================
# Grafana load balancer
# ==============================================================================

locals {
  # Plain http, always. A GCP load balancer from a Service is L4 — it passes
  # bytes through and terminates nothing — so claiming https here would only
  # advertise a scheme that does not answer. Worse, the `cookie_secure` that
  # used to come with it made the session cookie unsendable over the
  # connection that does work, so nobody could log in.
  #
  # Put a terminator in front, or give Grafana its own certificate (DEP-195),
  # and set `root_url` plus `security.cookie_secure` through `additional_values`.
  grafana_scheme = "http"

  grafana_service_annotations = var.grafana_load_balancer == null ? {} : merge(
    {
      # The same annotation the `load_balancers` module uses for the console.
      "networking.gke.io/load-balancer-type" = var.grafana_load_balancer.internal ? "Internal" : "External"
    },
    var.grafana_load_balancer.annotations,
  )

  grafana_load_balancer_values = var.grafana_load_balancer == null ? [] : [yamlencode({
    grafana = merge(
      {
        service = {
          type                     = "LoadBalancer"
          annotations              = local.grafana_service_annotations
          loadBalancerSourceRanges = var.grafana_load_balancer.ingress_cidr_blocks
        }
      },
      var.grafana_load_balancer.host == null ? {} : {
        "grafana.ini" = {
          # Grafana builds share links, alert notification links, and OAuth
          # redirect URIs from this. All three break silently when it disagrees
          # with the host users actually reach.
          server = { root_url = "${local.grafana_scheme}://${var.grafana_load_balancer.host}" }
        }
      },
    )
  })]
}

# The load balancer's own address, so `grafana_url` can name where Grafana
# actually answers rather than falling back to the in-cluster Service whenever no
# hostname was supplied.
#
# A data source rather than a resource attribute: the Service is created by Helm
# inside the monitoring module, so Terraform has no handle on it. Read after that
# module, and tolerant of an address that is not assigned yet — the cloud
# provisions the load balancer asynchronously, so the first apply can complete
# before an IP exists. `grafana_url` degrades to the in-cluster name in that
# window, and the next plan picks the address up.
data "kubernetes_service" "grafana" {
  count = var.grafana_load_balancer == null ? 0 : 1

  metadata {
    # The chart pins `grafana.fullnameOverride`, so the name is static.
    name      = "grafana"
    namespace = var.namespace
  }

  depends_on = [module.monitoring]
}

locals {
  # GCP and Azure hand out an IP; the `hostname` branch is there because a
  # cloud-specific annotation can produce one instead.
  grafana_load_balancer_address = one([
    for ing in try(data.kubernetes_service.grafana[0].status[0].load_balancer[0].ingress, []) :
    coalesce(try(ing.hostname, null), try(ing.ip, null))
    if coalesce(try(ing.hostname, null), try(ing.ip, null), "") != ""
  ])
}
