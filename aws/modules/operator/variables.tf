variable "name_prefix" {
  description = "Prefix for all resource names (replaces separate namespace and environment variables)"
  type        = string
  nullable    = false
}

variable "operator_version" {
  description = "Version of the Materialize operator to install"
  type        = string
  default     = "v25.3.0-beta.1" # META: helm-chart version
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
  nullable    = false
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
  default     = true
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


variable "aws_region" {
  description = "AWS region for the operator Helm values."
  type        = string
  nullable    = false
}

variable "aws_account_id" {
  description = "AWS account ID for the operator Helm values."
  type        = string
  nullable    = false
}

variable "use_self_signed_cluster_issuer" {
  description = "Whether to use a self-signed cluster issuer for cert-manager."
  type        = bool
  default     = false
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
