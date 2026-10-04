# Deploys the `materialize-monitoring` stack on GKE: Grafana, metrics via Thanos,
# logs via Loki, and the Alloy pipeline. This module owns the GCP side (a GCS
# bucket, Google service account, and Workload Identity binding per backend) and
# delegates everything in the cluster to the cloud-agnostic module shipped with
# the chart, so no Helm value paths live here.
#
# Operational notes:
#
#   * Workload Identity must be enabled on the cluster (`workload_pool`), or the
#     pods fall back to the node service account despite the bindings below.
#   * The `monitoring-crds` module creates the `monitoring` namespace and the
#     CRDs, so `create_namespace` defaults to false and the examples pass
#     `enable_monitoring_crds = false`. Pass its `namespace` output as
#     `namespace` (or keep a `depends_on`) or the release can race the namespace.
#   * The operator module installs metrics-server, which the Console needs. If
#     you disable it there, set `install_metrics_server = true` here.
#   * Bucket housekeeping (deleting noncurrent versions, soft delete off) always
#     runs. `logs_retention_days` and `metrics_retention_days` are opt-in
#     backstops only: Loki and Thanos enforce their own retention, and Thanos
#     keeps blocks per downsampling resolution (raw / 5m / 1h), so deleting
#     sooner removes blocks the compactor still needs.
#   * Grafana is ClusterIP unless `grafana_load_balancer` is set. Reach it with
#     `kubectl -n monitoring port-forward svc/grafana 3000:80` and
#     `terraform output -raw grafana_admin_password`.
#   * `node_selector` skips the Alloy agent DaemonSet, which must run on every
#     node. `tolerations` do reach it.
#   * GKE does not expose the full cAdvisor and kube-state-metrics surface, so a
#     few percentage-based dashboard panels stay empty. That is expected.
#
# One bucket per backend rather than shared with prefixes: lifecycle rules differ,
# IAM scoping is tighter, and Loki's `bucketNames` are not prefixes.

locals {
  # Must match the chart's ServiceAccount names for the Workload Identity members.
  # The monitoring module outputs them too, but reading that would be a dependency cycle.
  service_accounts = {
    loki   = "loki"
    thanos = "thanos-thanos"
  }

  # Not in the map above: the gateway binds to Cloud Monitoring, not a bucket.
  gateway_service_account = "alloy-gateway"

  # One Google service account covers both gateway roles, writing (export) and
  # reading (provider pull). Each role is granted only when its feature is on.
  provider_metrics_enabled = var.provider_metrics != null
  gateway_identity_enabled = var.enable_google_cloud_metrics || local.provider_metrics_enabled

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

  # Both backends authenticate as a service account, never with object ACLs.
  uniform_bucket_level_access = true

  versioning {
    enabled = var.enable_bucket_versioning
  }

  # Off: the default 7-day soft delete bills deleted objects as stored bytes, so
  # with versioning we would pay twice for everything the compactors delete.
  soft_delete_policy {
    retention_duration_seconds = 0
  }

  # Opt-in retention backstop; see the notes at the top of this file.
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

  # Versioning keeps a copy of everything the compactors delete; without this the
  # bucket grows without bound. Not gated on `enable_bucket_versioning`: turning
  # it off keeps old versions, which gating would strand. On a never-versioned
  # bucket the rule never matches.
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      days_since_noncurrent_time = 7
    }
  }

  # Safety net for access through the S3-compatible XML API, whose multipart
  # uploads strand billable parts. Loki and Thanos use the native Go client's
  # resumable uploads, which expire on their own, so this is a no-op by default.
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

  # Not truncated: `var.prefix` is capped at 17 so `-mzmon-thanos` fits the
  # 30-character account_id limit.
  account_id   = "${var.prefix}-mzmon-${each.key}"
  display_name = "materialize-monitoring ${each.key}"
  project      = var.project_id
}

# Scoped to the backend's own bucket. objectAdmin, not admin: neither backend
# administers the bucket itself.
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
# Separate from the loop above: the gateway writes and reads metrics, not
# objects, so it gets project-level roles and no bucket.

resource "google_service_account" "gateway" {
  count = local.gateway_identity_enabled ? 1 : 0

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

# Project-wide because Cloud Monitoring IAM has no per-resource read scoping; the
# chart values confine the pull. Predefined, not a custom role: a deleted custom
# role's ID stays reserved for days, which breaks destroy and re-create.
resource "google_project_iam_member" "gateway_monitoring_viewer" {
  count = local.provider_metrics_enabled ? 1 : 0

  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gateway[0].email}"
}

resource "google_service_account_iam_member" "gateway_workload_identity" {
  count = local.gateway_identity_enabled ? 1 : 0

  service_account_id = google_service_account.gateway[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${local.gateway_service_account}]"
}

# ==============================================================================
# Provider metrics: what the gateway pulls
# ==============================================================================
# Named, never discovered: the chart pulls exactly these resources. This module's
# own resources join the caller's unless `include_monitoring_resources` is false.

locals {
  provider_metrics_cloud_sql_instances = local.provider_metrics_enabled ? distinct(concat(
    var.provider_metrics.cloud_sql_instances,
    var.provider_metrics.include_monitoring_resources && local.create_grafana_database ? [module.grafana_database[0].instance_name] : [],
  )) : []

  provider_metrics_gcs_buckets = local.provider_metrics_enabled ? distinct(concat(
    var.provider_metrics.gcs_buckets,
    var.provider_metrics.include_monitoring_resources ? [for k in keys(local.service_accounts) : google_storage_bucket.telemetry[k].name] : [],
  )) : []

  # Optional fields are omitted rather than set to null, so the chart's own
  # defaults survive.
  provider_metrics_values = local.provider_metrics_enabled ? [yamlencode({
    pipeline = {
      metrics = {
        provider = {
          gcp = merge(
            {
              enabled   = true
              projectId = var.project_id
              cloudSql  = { instances = local.provider_metrics_cloud_sql_instances }
              gcs       = { buckets = local.provider_metrics_gcs_buckets }
              compute   = { regions = distinct(var.provider_metrics.compute_regions) }
            },
            var.provider_metrics.scrape_interval == null ? {} : { scrapeInterval = var.provider_metrics.scrape_interval },
            var.provider_metrics.importance == null ? {} : { metricImportance = var.provider_metrics.importance },
          )
        }
      }
    }
  })] : []
}

# ==============================================================================
# The stack
# ==============================================================================

module "monitoring" {
  # Pinned to a released tag. The module reads its chart version from the chart
  # beside it, so this ref alone sets the chart version.
  #
  # To develop against an unreleased module, use a *relative* path to a local
  # checkout (`../../../../materialize-monitoring/terraform/modules/materialize-monitoring`).
  # An absolute path copies the module without the chart, and sizing profiles break.
  #
  # The `/` in the tag needs Terraform >= 1.10 (hashicorp/terraform#35552).
  source = "github.com/MaterializeInc/materialize-monitoring//terraform/modules/materialize-monitoring?ref=materialize-monitoring/v0.30.0"

  namespace        = var.namespace
  create_namespace = var.create_namespace

  chart_version = var.chart_version

  # Null uses the monitoring module's default (they are `nullable = false` there).
  # None can be set through `additional_values`, so they must be forwarded.
  chart_registry         = var.chart_registry
  enable_monitoring_crds = var.enable_monitoring_crds
  install_timeout        = var.install_timeout

  sizing        = var.sizing
  node_selector = var.node_selector
  tolerations   = var.tolerations
  storage_class = var.storage_class
  min_zones     = var.min_zones

  materialize_instance_namespace = var.materialize_instance_namespace
  materialize_operator_namespace = var.materialize_operator_namespace
  install_metrics_server         = var.install_metrics_server

  grafana_admin_password = var.grafana_admin_password

  # In-cluster TLS defaults to on here rather than in the monitoring module: every
  # example in this repo installs cert-manager, other consumers may not.
  certificates_enabled       = var.certificates_enabled
  internal_tls               = coalesce(var.internal_tls, var.certificates_enabled ? "authenticate" : "off")
  issuer_ref                 = var.issuer_ref
  internal_issuer_ref        = var.internal_issuer_ref
  grafana_external_dns_names = var.grafana_external_dns_names
  certificate_duration       = var.certificate_duration
  certificate_renew_before   = var.certificate_renew_before

  # Explicit, not inferred from host/password: those can be unknown at plan time
  # (instance endpoint, generated password), but these conditions are plan-known.
  grafana_database_enabled                = local.create_grafana_database || var.grafana_database_host != null
  grafana_database_manage_password_secret = local.create_grafana_database || var.grafana_database_password != null

  # TODO: pass the Grafana Service port once the monitoring module accepts one.
  # The chart sets it (`grafana.service.port`, 80) and nothing here sets it on the
  # chart, so they agree by coincidence. In-cluster TLS will move that port.
  #
  # grafana_service_port = 80

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
    # Only set when the gateway uses Cloud Monitoring; it needs no bucket access.
    gateway_service_account_annotations = local.gateway_identity_enabled ? {
      "iam.gke.io/gcp-service-account" = google_service_account.gateway[0].email
    } : {}
  }

  google_cloud_metrics = var.enable_google_cloud_metrics ? {
    min_importance = var.google_cloud_metrics_min_importance
    prefix         = var.google_cloud_metrics_prefix
  } : null

  # Passed through; the monitoring module validates them and keeps credentials
  # out of the Helm values (they go in the gateway Secret).
  datadog_metrics = var.datadog_metrics
  datadog_api_key = var.datadog_api_key

  otlp_metrics             = var.otlp_metrics
  otlp_auth_header_secrets = var.otlp_auth_header_secrets
  otlp_auth_bearer_token   = var.otlp_auth_bearer_token

  # Passed through; the monitoring module validates them and fails the plan when
  # a receiver reads a key `alerting_receiver_secrets` does not set.
  alert_rules               = var.alert_rules
  alerting                  = var.alerting
  alerting_receiver_secrets = var.alerting_receiver_secrets
  alertmanager_namespace    = var.alertmanager_namespace

  # Computed values first, so `additional_values` overrides them.
  additional_values = concat(
    local.grafana_load_balancer_values,
    local.provider_metrics_values,
    var.additional_values,
  )

  depends_on = [
    google_storage_bucket_iam_member.telemetry,
    google_service_account_iam_member.workload_identity,
    google_project_iam_member.gateway_metric_writer,
    google_project_iam_member.gateway_monitoring_viewer,
    google_service_account_iam_member.gateway_workload_identity,
  ]
}

# ==============================================================================
# Grafana state database
# ==============================================================================
# Uses this repo's `database` module so Grafana's instance gets the same backup,
# maintenance, and private-networking settings as the Materialize database.

resource "random_password" "grafana_database" {
  count = var.grafana_database != null && var.grafana_database_password == null ? 1 : 0

  length = 32
  # Grafana reads this from a mounted file and operators paste it into psql;
  # alphanumeric avoids quoting problems.
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

  # A caller-supplied password wins; the random one is used only when this module
  # creates the instance. Not `coalesce`, which errors when every argument is
  # null, as in the default install with no database.
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
  # Always http: a GCP Service load balancer is L4 and terminates no TLS. Setting
  # `security.cookie_secure` without TLS stops the browser sending the session
  # cookie, so nobody can log in. Once something terminates TLS (DEP-195), set
  # `root_url` and `security.cookie_secure` through `additional_values`.
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
        service = merge(
          {
            type                     = "LoadBalancer"
            annotations              = local.grafana_service_annotations
            loadBalancerSourceRanges = var.grafana_load_balancer.ingress_cidr_blocks
          },
          # Pre-allocated, so the address is known at plan time without reading
          # the Service back.
          var.grafana_load_balancer.ip == null ? {} : {
            loadBalancerIP = var.grafana_load_balancer.ip
          },
        )
      },
      var.grafana_load_balancer.host == null ? {} : {
        "grafana.ini" = {
          # Share links, alert links, and OAuth redirect URIs are built from this
          # and break silently if it differs from the host users reach.
          server = { root_url = "${local.grafana_scheme}://${var.grafana_load_balancer.host}" }
        }
      },
    )
  })]
}

# Reads the load balancer address so `grafana_url` can use it when no hostname is
# set. A data source because Helm creates the Service. The address is assigned
# asynchronously, so after the first apply `grafana_url` may still show the
# in-cluster name; the next plan picks the address up.
data "kubernetes_service" "grafana" {
  # Skipped when the address was pre-allocated. Both conditions are plan-known.
  count = var.grafana_load_balancer == null || var.grafana_load_balancer.ip != null ? 0 : 1

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
  grafana_load_balancer_address = try(var.grafana_load_balancer.ip, null) != null ? (
    var.grafana_load_balancer.ip
    ) : one([
      for ing in try(data.kubernetes_service.grafana[0].status[0].load_balancer[0].ingress, []) :
      coalesce(try(ing.hostname, null), try(ing.ip, null))
      if coalesce(try(ing.hostname, null), try(ing.ip, null), "") != ""
  ])
}
