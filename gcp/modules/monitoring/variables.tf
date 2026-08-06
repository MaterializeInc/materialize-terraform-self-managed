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
