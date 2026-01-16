variable "namespace" {
  description = "Kubernetes namespace for Grafana"
  type        = string
  default     = "monitoring"
  nullable    = false
}

variable "create_namespace" {
  description = "Whether to create the namespace"
  type        = bool
  default     = false
  nullable    = false
}

variable "chart_version" {
  description = "Version of the Grafana helm chart"
  type        = string
  default     = "10.5.0"
  nullable    = false
}

variable "install_timeout" {
  description = "Timeout for installing the Grafana helm chart, in seconds"
  type        = number
  default     = 600
  nullable    = false
}

variable "prometheus_url" {
  description = "URL of the Prometheus server to use as data source"
  type        = string
  nullable    = false
}

variable "admin_password" {
  description = "Admin password for Grafana. If not set, a random password will be generated."
  type        = string
  default     = null
  sensitive   = true
}

variable "storage_size" {
  description = "Storage size for Grafana persistent volume"
  type        = string
  default     = "10Gi"
  nullable    = false
}

variable "node_selector" {
  description = "Node selector for Grafana pods"
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "tolerations" {
  description = "Tolerations for Grafana pods"
  type = list(object({
    key      = string
    value    = optional(string)
    operator = optional(string, "Equal")
    effect   = string
  }))
  default  = []
  nullable = false
}

variable "resources" {
  description = "Resource requests and limits for Grafana"
  type = object({
    requests = optional(object({
      cpu    = optional(string, "100m")
      memory = optional(string, "128Mi")
    }))
    limits = optional(object({
      cpu    = optional(string, "500m")
      memory = optional(string, "512Mi")
    }))
  })
  default = {
    requests = {}
    limits   = {}
  }
  nullable = false
}
