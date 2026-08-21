variable "kubeconfig_path" {
  description = "Path to the kubeconfig for the target cluster"
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Kubeconfig context to use. Null uses the current context."
  type        = string
  default     = null
}

variable "name_prefix" {
  description = "Prefix for named resources"
  type        = string
  default     = "materialize"
}

variable "license_key" {
  description = "Materialize license key"
  type        = string
  sensitive   = true
}

variable "metadata_backend_url" {
  description = "PostgreSQL connection URL for the metadata backend, e.g. postgres://user:pass@host:5432/materialize"
  type        = string
  sensitive   = true
}

variable "persist_backend_url" {
  description = "S3-compatible connection URL for the persist backend, e.g. s3://user:pass@bucket/prefix?endpoint=https%3A%2F%2Fhost&region=region"
  type        = string
  sensitive   = true
}

variable "operator_version" {
  description = "Version of the Materialize operator Helm chart"
  type        = string
  default     = "v26.37.0" # META: helm-chart version
}

variable "helm_chart" {
  description = "Chart name from repository or local path to chart. For local charts, set the path to the chart directory."
  type        = string
  default     = "materialize-operator"
}

variable "use_local_chart" {
  description = "Whether to use a local chart instead of one from a repository"
  type        = bool
  default     = false
}

variable "orchestratord_version" {
  description = "Orchestratord image tag override. Null uses the chart default."
  type        = string
  default     = null
}

variable "environmentd_version" {
  description = "Environmentd version override. Null uses the materialize-instance module default."
  type        = string
  default     = null
}
