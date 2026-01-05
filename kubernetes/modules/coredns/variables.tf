variable "kubeconfig_data" {
  description = "Kubeconfig data for kubectl commands"
  type        = string
  nullable    = false
  validation {
    condition     = length(var.kubeconfig_data) > 0
    error_message = "kubeconfig_data must be a non-empty string"
  }
}

variable "disable_default_coredns" {
  description = "Whether to scale down the default kube-dns deployment"
  type        = bool
  default     = true
  nullable    = false
}

variable "disable_default_coredns_autoscaler" {
  description = "Whether to scale down the default kube-dns autoscaler deployment"
  type        = bool
  default     = true
  nullable    = false
}

variable "create_coredns_service_account" {
  description = "Whether to create the CoreDNS service account"
  type        = bool
  default     = false
  nullable    = false
}

variable "replicas" {
  description = "Number of CoreDNS replicas"
  type        = number
  default     = 2
  nullable    = false
}

variable "node_selector" {
  description = "Node selector for CoreDNS deployment"
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "coredns_deployment_to_scale_down" {
  description = "Name of the CoreDNS deployment to scale down"
  type        = string
  default     = "coredns"
  nullable    = false
}

variable "coredns_autoscaler_deployment_to_scale_down" {
  description = "Name of the CoreDNS autoscaler deployment to scale down"
  type        = string
  default     = "coredns-autoscaler"
  nullable    = false
}

variable "coredns_version" {
  description = "CoreDNS image version"
  type        = string
  default     = "1.11.1"
  nullable    = false
}

variable "cpu_request" {
  description = "CPU request for CoreDNS container"
  type        = string
  default     = "100m"
  nullable    = false
}

variable "memory_request" {
  description = "Memory request for CoreDNS container"
  type        = string
  default     = "170Mi"
  nullable    = false
}

variable "memory_limit" {
  description = "Memory limit for CoreDNS container"
  type        = string
  default     = "170Mi"
  nullable    = false
}

# HPA Configuration
variable "hpa_min_replicas" {
  description = "Minimum number of replicas for HPA"
  type        = number
  default     = 2
  nullable    = false
}

variable "hpa_max_replicas" {
  description = "Maximum number of replicas for HPA"
  type        = number
  default     = 100
  nullable    = false
}

variable "hpa_cpu_target_utilization" {
  description = "Target CPU utilization percentage for HPA"
  type        = number
  default     = 60
  nullable    = false
}

variable "hpa_memory_target_utilization" {
  description = "Target memory utilization percentage for HPA"
  type        = number
  default     = 50
  nullable    = false
}

variable "hpa_scale_up_stabilization_window" {
  description = "Stabilization window for scale up in seconds"
  type        = number
  default     = 180
  nullable    = false
}

variable "hpa_scale_up_pods_per_period" {
  description = "Maximum pods to add per period during scale up"
  type        = number
  default     = 4
  nullable    = false
}

variable "hpa_scale_up_percent_per_period" {
  description = "Maximum percent to scale up per period"
  type        = number
  default     = 100
  nullable    = false
}

variable "hpa_scale_down_stabilization_window" {
  description = "Stabilization window for scale down in seconds"
  type        = number
  default     = 600
  nullable    = false
}

variable "hpa_scale_down_percent_per_period" {
  description = "Maximum percent to scale down per period"
  type        = number
  default     = 100
  nullable    = false
}

variable "hpa_policy_period_seconds" {
  description = "Period in seconds for scaling policies"
  type        = number
  default     = 15
  nullable    = false
}
