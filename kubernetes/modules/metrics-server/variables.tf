variable "namespace" {
  description = "Kubernetes namespace for metrics-server"
  type        = string
  default     = "monitoring"
  nullable    = false
}

variable "create_namespace" {
  description = "Whether to create the namespace"
  type        = bool
  default     = true
  nullable    = false
}

variable "release_name" {
  description = "Name for the Helm release"
  type        = string
  default     = "metrics-server"
  nullable    = false
}

variable "chart_version" {
  description = "Version of the metrics-server Helm chart"
  type        = string
  default     = "3.12.2"
  nullable    = false
}

variable "skip_tls_verification" {
  description = "Whether to skip TLS verification when connecting to kubelets"
  type        = bool
  default     = true
  nullable    = false
}

variable "metrics_enabled" {
  description = "Whether to enable metrics collection"
  type        = bool
  default     = true
  nullable    = false
}

variable "node_selector" {
  description = "Node selector for metrics-server pods"
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "tolerations" {
  description = "Tolerations for metrics-server pods"
  type = list(object({
    key      = string
    value    = optional(string)
    operator = optional(string, "Equal")
    effect   = string
  }))
  default  = []
  nullable = false
}
