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

variable "helm_repo_username" {
  description = "Username to access the Karpenter helm repo."
  type        = string
  nullable    = false
}

variable "helm_repo_password" {
  description = "Password to access the Karpenter helm repo."
  type        = string
  nullable    = false
  sensitive   = true
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
