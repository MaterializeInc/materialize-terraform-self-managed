variable "prefix" {
  description = "Prefix for the bucket and service-account names this module creates. Capped at 17 characters so the longest generated name still fits: a service account `account_id` is limited to 30, and `-mzmon-thanos` takes 13 of them."
  type        = string
  nullable    = false

  # Truncating instead would be worse than failing here. At 23 characters
  # `-mzmon-<backend>` loses the backend entirely, so loki and thanos both
  # resolve to `<prefix>-mzmon-` — a duplicate account_id, and a trailing
  # hyphen that GCP rejects. Fail at plan with a name rather than at apply
  # with a collision.
  validation {
    condition     = length(var.prefix) <= 17
    error_message = "prefix must be at most 17 characters; a service account account_id is capped at 30 and `-mzmon-thanos` uses 13."
  }
}

variable "project_id" {
  description = "GCP project holding the buckets and service accounts."
  type        = string
  nullable    = false
}

variable "region" {
  description = "Location for the telemetry buckets."
  type        = string
  nullable    = false
}

variable "namespace" {
  description = "Namespace the monitoring stack is installed into. Also the namespace half of every Workload Identity member."
  type        = string
  default     = "monitoring"
  nullable    = false
}

variable "create_namespace" {
  description = "Whether the monitoring module creates the namespace. False by default because the operator module already creates `monitoring`."
  type        = bool
  default     = false
  nullable    = false
}

# ==============================================================================
# Buckets
# ==============================================================================

variable "bucket_force_destroy" {
  description = "Allow Terraform to delete non-empty buckets. Leave false outside throwaway environments — destroying it takes the telemetry with it."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_bucket_versioning" {
  description = "Enable versioning on the telemetry buckets. Versioning is the disaster-recovery primitive for both Loki and Thanos, neither of which has a native snapshot."
  type        = bool
  default     = true
  nullable    = false
}

variable "logs_retention_days" {
  description = "Delete Loki objects after this many days. Null disables the lifecycle rule and leaves retention to Loki's compactor."
  type        = number
  default     = null
}

variable "metrics_retention_days" {
  description = <<-EOT
    Delete Thanos objects after this many days. Null disables the lifecycle rule.

    Leave it null unless you know what you are doing: Thanos's compactor already enforces
    retention per downsampling resolution (raw / 5m / 1h), and a bucket rule that deletes
    sooner removes blocks the compactor still expects to find.
  EOT
  type        = number
  default     = null
}

variable "labels" {
  description = "Labels applied to the buckets this module creates."
  type        = map(string)
  default     = {}
  nullable    = false
}

# ==============================================================================
# Passed through to the monitoring module
# ==============================================================================

variable "chart_registry" {
  description = "OCI registry holding the materialize-monitoring charts. Override for a mirrored or air-gapped registry; there is no way to reach this through `additional_values`."
  type        = string
  default     = null
}

variable "enable_monitoring_crds" {
  description = "Install the materialize-monitoring-crds chart (prometheus-operator and grafana-operator CRDs). Set false when the cluster already has them from elsewhere, such as kube-prometheus-stack or a platform team that owns CRDs centrally. Null uses the monitoring module's default."
  type        = bool
  default     = null
}

variable "install_timeout" {
  description = "Timeout for each Helm release, in seconds. Null uses the monitoring module's default, which is well above Helm's 300s because a first install brings up Loki, Thanos, Grafana, and both Alloy roles together."
  type        = number
  default     = null
}

variable "chart_version" {
  description = "Override the materialize-monitoring chart version. Leave null to use the version the pinned module ships with — the two are one release."
  type        = string
  default     = null
}

variable "sizing" {
  description = "Deployment size: small, medium, or large. The chart's defaults are medium."
  type        = string
  default     = "medium"
  nullable    = false
}

variable "materialize_instance_namespace" {
  description = "Namespace the Materialize instance runs in."
  type        = string
  default     = "materialize-environment"
  nullable    = false
}

variable "materialize_operator_namespace" {
  description = "Namespace the Materialize operator runs in."
  type        = string
  default     = "materialize"
  nullable    = false
}

variable "install_metrics_server" {
  description = "Install metrics-server as part of the monitoring stack. Set true when the operator module has `install_metrics_server = false`, or the Materialize Console loses cluster metrics."
  type        = bool
  default     = false
  nullable    = false
}

variable "node_selector" {
  description = "Node selector for the centralized monitoring workloads. Not applied to the Alloy agent DaemonSet, which must reach every node."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "storage_class" {
  description = <<-EOT
    StorageClass for the PVC-backed monitoring workloads (Alertmanager, the Loki ruler, and Thanos
    receive/compactor/store-gateway). Null uses the cluster default.

    Must be a Hyperdisk class on C4/C4A/N4, which take only Hyperdisk — every default GKE class is
    Persistent Disk and fails to attach there. The examples create one and pass it here.
  EOT
  type        = string
  default     = null
}

variable "enable_google_cloud_metrics" {
  description = <<-EOT
    Also export metrics to Google Cloud Monitoring from the Alloy gateway. Thanos is unaffected.

    Creates a service account with `roles/monitoring.metricWriter` (write-only) and binds the
    gateway's in-cluster ServiceAccount to it via Workload Identity.
  EOT
  type        = bool
  default     = false
  nullable    = false
}

variable "google_cloud_metrics_min_importance" {
  description = "Metric tier to export: `essential`, `recommended`, `extended`, `diagnostic`, or `all`. Each tier includes the ones below it. A cost control — Cloud Monitoring bills per custom metric."
  type        = string
  default     = "recommended"
  nullable    = false
}

variable "google_cloud_metrics_prefix" {
  description = "Metric name prefix in Cloud Monitoring. Null uses the chart's default (`workload.googleapis.com/mzmon`)."
  type        = string
  default     = null
}

variable "tolerations" {
  description = "Tolerations for the monitoring workloads, including the Alloy agent DaemonSet."
  type = list(object({
    key      = optional(string)
    operator = optional(string, "Equal")
    value    = optional(string)
    effect   = optional(string)
  }))
  default  = []
  nullable = false
}

variable "grafana_admin_password" {
  description = "Grafana admin password. Generated when null."
  type        = string
  default     = null
  sensitive   = true
}

variable "additional_values" {
  description = "Raw YAML documents appended to the Helm values, last, so they override everything the modules compute."
  type        = list(string)
  default     = []
  nullable    = false
}

# ==============================================================================
# Grafana state database
# ==============================================================================

variable "grafana_database" {
  description = <<-EOT
    Provision a dedicated Cloud SQL PostgreSQL instance for Grafana's own state.

    Grafana keeps users, service accounts and tokens, annotations, dashboard versions and
    permissions, preferences, and alert-rule state in a database separate from the observability
    data in Loki and Thanos. The chart default is SQLite on an `emptyDir`, so all of it is lost on
    every restart, upgrade, and reschedule. That is tolerable while Grafana is reached through
    `port-forward` and not once it is exposed, which is why this and `grafana_load_balancer`
    belong in the same change.

    Dedicated rather than a database inside the Materialize instance: it keeps Grafana's blast
    radius away from Materialize's metadata, and it is the same shape the AWS and Azure wrappers
    use, where sharing is not cleanly possible at all.

    `db-f1-micro` is enough. Grafana's state is small and its query rate is a handful per page
    load; this is a durability decision, not a capacity one.

    Null leaves Grafana on SQLite. Point at a database you already run with the
    `grafana_database_*` variables instead.

    The examples enable this whenever `enable_observability` is on: durability is the
    production default, and the cost of the smallest instance is well below the cost of
    silently losing everything a user built in Grafana.
  EOT

  type = object({
    network_id = string

    tier                           = optional(string, "db-f1-micro")
    db_version                     = optional(string, "POSTGRES_16")
    edition                        = optional(string, "ENTERPRISE")
    disk_size                      = optional(number, 10)
    backup_enabled                 = optional(bool, true)
    point_in_time_recovery_enabled = optional(bool, false)
  })

  default = null

  validation {
    condition     = var.grafana_database == null || var.grafana_database_host == null
    error_message = "Set either grafana_database (this module creates the instance) or grafana_database_host (you point at an existing one), not both."
  }
}

# The five below point Grafana at a database this module does not create. They
# are forwarded to the monitoring module untouched, and are mutually exclusive
# with `grafana_database`.

variable "grafana_database_host" {
  description = "Hostname or IP of an existing PostgreSQL database for Grafana's state. Mutually exclusive with `grafana_database`. Host only — the port is `grafana_database_port`."
  type        = string
  default     = null
}

variable "grafana_database_port" {
  description = "Port for `grafana_database_host`."
  type        = number
  default     = 5432
  nullable    = false
}

variable "grafana_database_name" {
  description = "Name of the database Grafana owns."
  type        = string
  default     = "grafana"
  nullable    = false
}

variable "grafana_database_user" {
  description = "Database user Grafana connects as. Must be able to create objects in `grafana_database_name`: Grafana runs schema migrations at startup, so a read/write-only grant fails them. A Cloud SQL user created through the API gets `cloudsqlsuperuser`, which satisfies this."
  type        = string
  default     = "grafana"
  nullable    = false
}

variable "grafana_database_password" {
  description = "Password for `grafana_database_user`. Generated when this module creates the instance. Null with an external host means the connection needs no password — the Cloud SQL Auth Proxy sidecar shape."
  type        = string
  default     = null
  sensitive   = true
}

variable "grafana_database_ssl_mode" {
  description = "libpq SSL mode for the Grafana database connection. `require` encrypts but does not authenticate the server; `verify-full` also authenticates it but needs the instance's server CA mounted, which this module does not do — supply `grafana.ini.database.ca_cert_path` and the matching mount through `additional_values` for that."
  type        = string
  default     = "require"
  nullable    = false
}

# ==============================================================================
# Grafana load balancer
# ==============================================================================

variable "grafana_load_balancer" {
  description = <<-EOT
    Expose Grafana through a GCP load balancer, provisioned from the `LoadBalancer` Service the
    chart renders.

    A Service rather than an Ingress: this is the shape GKE takes without an ingress controller
    installed, and it matches what the `load_balancers` module already does for the Materialize
    console. The two are not an L7-versus-L4 choice — both ask GCP for a load balancer — so pick
    by what the cluster's controllers actually consume.

    Internal by default, and `ingress_cidr_blocks` is required rather than defaulted: it becomes
    `loadBalancerSourceRanges` on the Service, and the chart refuses to render a `LoadBalancer`
    with no allowlist. On an internal load balancer pass your VPC CIDR; the chart cannot see the
    `Internal` annotation, so the allowlist is what makes the intent legible to it.

    `host` is optional because a GCP load balancer answers on an IP. Set it once DNS exists —
    Grafana builds share links, alert notification links, and OAuth redirect URIs from
    `root_url`, and the chart warns while it is unset.

    `ip` pre-allocates the address instead of letting GCP pick one. Supplying it is what makes
    `grafana_url` known at plan time — without it the module has to read the Service back after
    apply, which is why a fresh apply can still report the in-cluster name. Reserve it with
    `google_compute_address`: `INTERNAL` in the load balancer's subnetwork for an internal one,
    `EXTERNAL` and regional otherwise.

    Null leaves Grafana on a ClusterIP Service, reachable only with `kubectl port-forward`.
  EOT

  type = object({
    ingress_cidr_blocks = list(string)

    internal    = optional(bool, true)
    host        = optional(string, null)
    ip          = optional(string, null)
    annotations = optional(map(string), {})
  })

  default = null

  validation {
    condition = var.grafana_load_balancer == null ? true : (
      length(var.grafana_load_balancer.ingress_cidr_blocks) > 0 && alltrue([
        for cidr in var.grafana_load_balancer.ingress_cidr_blocks : can(cidrhost(cidr, 0))
      ])
    )
    error_message = "grafana_load_balancer.ingress_cidr_blocks must be non-empty and contain valid CIDR notation. On an internal load balancer, pass your VPC CIDR."
  }


  validation {
    condition = var.grafana_load_balancer == null ? true : (
      var.grafana_load_balancer.internal
      || !anytrue([
        for cidr in coalesce(var.grafana_load_balancer.ingress_cidr_blocks, []) :
        contains(["0.0.0.0/0", "::/0"], trimspace(cidr))
      ])
      # The acknowledgement is the chart's own `connections.grafana.allowPublicAccess`,
      # set through `additional_values` like any other chart value. Deliberately not
      # a variable of its own: there should be exactly one way to say this, and
      # saying it should take a moment's thought.
      || anytrue([
        for doc in var.additional_values :
        try(yamldecode(doc).connections.grafana.allowPublicAccess, false)
      ])
    )
    error_message = <<-EOT
      grafana_load_balancer is public (internal = false) with an unrestricted allowlist (0.0.0.0/0 or ::/0).
      Narrow ingress_cidr_blocks to the ranges that should reach Grafana.
      Every datasource behind Grafana reads every metric in Thanos and every log in the tenant, and
      until an identity provider is configured the generated admin password is the whole of the
      access control — which is why this is refused here but merely defaulted for the Materialize
      load balancers.
      If the allowlist is enforced somewhere this module cannot see, acknowledge it through the
      chart: additional_values = [yamlencode({ connections = { grafana = { allowPublicAccess = true } } })].
    EOT
  }
}
