variable "name_prefix" {
  description = "Prefix for the bucket and IAM role names this module creates. Capped at 40 characters so the longest generated name still fits: S3 bucket names are limited to 63, and `-mzmon-metrics-` plus the 8-character random suffix takes 23."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.name_prefix) <= 40
    error_message = "name_prefix must be at most 40 characters; S3 bucket names are capped at 63 and `-mzmon-metrics-` plus the random suffix uses 23."
  }
}

variable "region" {
  description = "AWS region the buckets live in. Passed explicitly rather than read from a data source, matching the rest of this repository."
  type        = string
  nullable    = false
}

variable "namespace" {
  description = "Namespace the monitoring stack is installed into. Also the namespace half of every IRSA trust-policy subject."
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
# Cluster identity
# ==============================================================================

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider, from the EKS module."
  type        = string
  nullable    = false
}

variable "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster, from the EKS module."
  type        = string
  nullable    = false
}

variable "iam_permissions_boundary" {
  description = "Optional permissions boundary applied to the IAM roles this module creates. No other AWS module in this repository takes one yet; the intent is that they should, and this is the first. Leaving it null keeps the previous behaviour, so adding it elsewhere later is additive."
  type        = string
  default     = null
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

variable "bucket_encryption_mode" {
  description = "Server-side encryption for the telemetry buckets. SSE-S3 by default; SSE-KMS requires `bucket_kms_key_arn` and grants the two backend roles `kms:Decrypt` and `kms:GenerateDataKey` on that key. Matches the option `aws/modules/storage` offers for the Materialize persist bucket."
  type        = string
  default     = "SSE-S3"
  nullable    = false

  validation {
    condition     = contains(["SSE-S3", "SSE-KMS"], var.bucket_encryption_mode)
    error_message = "bucket_encryption_mode must be either \"SSE-S3\" or \"SSE-KMS\"."
  }
}

variable "bucket_kms_key_arn" {
  description = "ARN of the KMS key to use when `bucket_encryption_mode` is SSE-KMS. A customer-managed key, not an alias — the IAM grant needs the ARN. Bucket Keys are enabled alongside it, because both backends write enough small objects for per-object KMS calls to show up on the bill."
  type        = string
  default     = null
}

variable "enable_bucket_versioning" {
  description = "Enable versioning on the telemetry buckets. Versioning is the disaster-recovery primitive for both Loki and Thanos, neither of which has a native snapshot."
  type        = bool
  default     = true
  nullable    = false
}

variable "logs_retention_days" {
  description = "Expire Loki objects after this many days. Null disables the lifecycle rule and leaves retention entirely to Loki's compactor."
  type        = number
  default     = null
}

variable "metrics_retention_days" {
  description = <<-EOT
    Expire Thanos objects after this many days. Null disables the lifecycle rule.

    Leave it null unless you know what you are doing: Thanos's compactor already enforces
    retention per downsampling resolution (raw / 5m / 1h), and a bucket rule that expires
    sooner deletes blocks the compactor still expects to find.
  EOT
  type        = number
  default     = null
}

variable "tags" {
  description = "Tags applied to the resources this module creates."
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
  description = "StorageClass for the PVC-backed monitoring workloads (Alertmanager, the Loki ruler, and Thanos receive/compactor/store-gateway). Null uses whatever class the cluster marks default; the examples pass the `gp3` class from the `ebs-csi-driver` module."
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
