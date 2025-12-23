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
  default     = "70Mi"
  nullable    = false
}

variable "memory_limit" {
  description = "Memory limit for CoreDNS container"
  type        = string
  default     = "170Mi"
  nullable    = false
}
