variable "name_prefix" {
  description = "Prefix for all resource names."
  type        = string
  nullable    = false
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  nullable    = false
}

variable "cluster_endpoint" {
  description = "Endpoint of the EKS cluster's Kubernetes API server."
  type        = string
  nullable    = false
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS cluster's OIDC provider."
  type        = string
  nullable    = false
}

variable "cluster_oidc_issuer_url" {
  description = "URL of the EKS cluster's OIDC issuer."
  type        = string
  nullable    = false
}

variable "node_selector" {
  description = "Node selector for the Karpenter controller pods."
  type        = map(string)
  nullable    = false
}

variable "helm_chart_version" {
  description = "Version of the Karpenter helm chart to install."
  type        = string
  default     = "1.8.1"
  nullable    = false
}

variable "vm_memory_overhead_percent" {
  description = "Reduction in memory from advertized, to account for VM overhead."
  type        = number
  default     = 0.05
  nullable    = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "iam_permissions_boundary" {
  description = "ARN of the IAM permissions boundary to attach to all IAM roles created by this module. Required for BYOC deployments."
  type        = string
  default     = null
}

variable "enable_service_monitor" {
  description = "Create a ServiceMonitor for the Karpenter controller's metrics. The prometheus-operator CRDs must be installed before this module, or the chart leaves the ServiceMonitor out."
  type        = bool
  default     = false
  nullable    = false
}

variable "service_monitor_instance_types" {
  description = "Instance types to keep offering-availability metrics for, which drop to 0 when EC2 has no capacity for a type in a zone. Pass the types the node pools allow. The metric is dropped for every other type, and entirely when this is empty, since Karpenter publishes it for every type in the region."
  type        = list(string)
  default     = []
  nullable    = false
}
