variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  nullable    = false
}

variable "operator_version" {
  description = "Version of the Materialize operator Helm chart to install"
  type        = string
  default     = "v26.7.0" # META: helm-chart version
  nullable    = false
}

variable "orchestratord_version" {
  description = "Version of the Materialize orchestrator image. Defaults to operator_version if not set."
  type        = string
  default     = null
}

variable "helm_repository" {
  description = "Repository URL for the Materialize operator Helm chart"
  type        = string
  default     = "https://materializeinc.github.io/materialize/"
  nullable    = false
}

variable "helm_chart" {
  description = "Chart name from repository or local path to chart"
  type        = string
  default     = "materialize-operator"
  nullable    = false
}

variable "use_local_chart" {
  description = "Whether to use a local chart instead of one from a repository"
  type        = bool
  default     = false
  nullable    = false
}

variable "operator_namespace" {
  description = "Namespace for the Materialize operator"
  type        = string
  default     = "materialize"
  nullable    = false
}

variable "create_namespace" {
  description = "Whether to create the operator namespace"
  type        = bool
  default     = true
  nullable    = false
}

variable "monitoring_namespace" {
  description = "Namespace for monitoring resources"
  type        = string
  default     = "monitoring"
  nullable    = false
}

variable "create_monitoring_namespace" {
  description = "Whether to create the monitoring namespace"
  type        = bool
  default     = true
  nullable    = false
}

# Cloud provider configuration - optional for local/kind deployments
variable "cloud_provider_config" {
  description = "Cloud provider configuration for the operator. Set to null for local/kind deployments."
  type = object({
    type   = string           # "aws", "gcp", "azure", or "local"
    region = optional(string) # Cloud region (required for cloud providers)
    providers = optional(object({
      aws = optional(object({
        enabled   = bool
        accountID = string
      }))
      gcp = optional(object({
        enabled = bool
      }))
      azure = optional(object({
        enabled = bool
      }))
    }))
  })
  default  = null
  nullable = true
}

variable "install_metrics_server" {
  description = "Whether to install the metrics-server"
  type        = bool
  default     = true
  nullable    = false
}

variable "metrics_server_version" {
  description = "Version of metrics-server to install"
  type        = string
  default     = "3.12.2"
  nullable    = false
}

variable "metrics_server_values" {
  description = "Configuration values for metrics-server"
  type = object({
    metrics_enabled       = string
    skip_tls_verification = bool
  })
  default = {
    metrics_enabled       = "true"
    skip_tls_verification = true
  }
  nullable = false
}

# Deprecated variables - use helm_values instead
variable "enable_license_key_checks" {
  description = "DEPRECATED: Use helm_values.operator.args.enableLicenseKeyChecks instead. Enable license key checks."
  type        = bool
  default     = true
  nullable    = false
}

variable "swap_enabled" {
  description = "DEPRECATED: Use helm_values.operator.clusters.swap_enabled instead. Whether to enable swap."
  type        = bool
  default     = true
}

variable "tolerations" {
  description = "DEPRECATED: Use helm_values.operator.tolerations instead. Tolerations for operator pods."
  type = list(object({
    key      = string
    value    = optional(string)
    operator = optional(string, "Equal")
    effect   = string
  }))
  default  = []
  nullable = false
}

variable "instance_pod_tolerations" {
  description = "DEPRECATED: Use helm_values.environmentd.tolerations instead. Tolerations for Materialize workloads."
  type = list(object({
    key      = string
    value    = optional(string)
    operator = optional(string, "Equal")
    effect   = string
  }))
  default  = []
  nullable = false
}

variable "operator_node_selector" {
  description = "DEPRECATED: Use helm_values.operator.nodeSelector instead. Node selector for operator pods."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "instance_node_selector" {
  description = "DEPRECATED: Use helm_values.environmentd.nodeSelector instead. Node selector for Materialize workloads."
  type        = map(string)
  default     = {}
  nullable    = false
}
