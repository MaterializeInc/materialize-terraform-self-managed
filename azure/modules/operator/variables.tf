variable "name_prefix" {
  description = "Prefix for all resource names (replaces separate namespace and environment variables)"
  type        = string
  nullable    = false
}

variable "operator_version" {
  description = "Version of the Materialize operator to install"
  type        = string
  default     = "v26.7.0" # META: helm-chart version
  nullable    = false
}

variable "orchestratord_version" {
  description = "Version of the Materialize orchestrator to install"
  type        = string
  default     = null
}

variable "helm_repository" {
  description = "Repository URL for the Materialize operator Helm chart. Leave empty if using local chart."
  type        = string
  default     = "https://materializeinc.github.io/materialize/"
  nullable    = false
}

variable "helm_chart" {
  description = "Chart name from repository or local path to chart. For local charts, set the path to the chart directory."
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

variable "helm_values" {
  description = "Values to pass to the Helm chart"
  type        = any
  default     = {}
}

variable "operator_namespace" {
  description = "Namespace for the Materialize operator"
  type        = string
  default     = "materialize"
  nullable    = false
}

variable "monitoring_namespace" {
  description = "Namespace for monitoring resources"
  type        = string
  default     = "monitoring"
  nullable    = false
}

variable "metrics_server_version" {
  description = "Version of metrics-server to install"
  type        = string
  default     = "3.12.2"
  nullable    = false
}

variable "install_metrics_server" {
  description = "Whether to install the metrics-server"
  type        = bool
  default     = false
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

variable "location" {
  description = "The location of the Azure subscription"
  type        = string
  nullable    = false
}

variable "enable_license_key_checks" {
  description = "Enable license key checks."
  type        = bool
  default     = true
  nullable    = false
}

variable "swap_enabled" {
  description = "Whether to enable swap on the local NVMe disks."
  type        = bool
  default     = true
}

variable "tolerations" {
  description = "Tolerations for operator pods and metrics-server."
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
  description = "Tolerations for Materialize instance workloads (environmentd, clusterd, balancerd, console)."
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
  description = "Node selector for operator pods and metrics-server."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "instance_node_selector" {
  description = "Node selector for Materialize workloads (environmentd, clusterd, balancerd, console)."
  type        = map(string)
  default     = {}
  nullable    = false
}
