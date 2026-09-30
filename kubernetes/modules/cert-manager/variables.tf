variable "namespace" {
  description = "The name of the namespace in which cert-manager will be installed."
  type        = string
  nullable    = false
  default     = "cert-manager"
}

variable "install_timeout" {
  description = "Timeout for installing the cert-manager helm chart, in seconds."
  type        = number
  nullable    = false
  default     = 300
}

variable "chart_version" {
  description = "Version of the cert-manager helm chart to install."
  type        = string
  nullable    = false
  default     = "v1.18.0"
}

variable "node_selector" {
  description = "Node selector for cert-manager pods."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "tolerations" {
  description = "Tolerations for cert-manager pods."
  type = list(object({
    key      = string
    value    = optional(string)
    operator = optional(string, "Equal")
    effect   = string
  }))
  default  = []
  nullable = false
}

variable "enable_service_monitor" {
  description = "Create a ServiceMonitor for the cert-manager controller, webhook and cainjector. The prometheus-operator CRDs must be installed before this module; the chart does not check, so the install fails without them."
  type        = bool
  default     = false
  nullable    = false
}
