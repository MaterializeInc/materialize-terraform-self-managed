variable "subscription_id" {
  description = "The ID of the Azure subscription"
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group"
  type        = string
}

variable "location" {
  description = "The location of the Azure subscription"
  type        = string
}

variable "prefix" {
  description = "The prefix for resource naming"
  type        = string
}

variable "vnet_name" {
  description = "The name of the virtual network"
  type        = string
}

variable "subnet_name" {
  description = "The name of the subnet"
  type        = string
}

variable "subnet_id" {
  description = "The ID of the subnet"
  type        = string
}

variable "kubernetes_version" {
  description = "The Kubernetes version"
  type        = string
}

variable "service_cidr" {
  description = "The service CIDR for the AKS cluster"
  type        = string
}

variable "default_node_pool_vm_size" {
  description = "The VM size for the default node pool"
  type        = string
}

variable "default_node_pool_node_count" {
  description = "The node count for the default node pool"
  type        = number
}

variable "nodepool_vm_size" {
  description = "The VM size for the Materialize node pool"
  type        = string
}

variable "auto_scaling_enabled" {
  description = "Whether auto scaling is enabled for the node pool"
  type        = bool
}

variable "min_nodes" {
  description = "The minimum number of nodes in the node pool"
  type        = number
}

variable "max_nodes" {
  description = "The maximum number of nodes in the node pool"
  type        = number
}

variable "node_count" {
  description = "The initial node count for the node pool"
  type        = number
}

variable "disk_size_gb" {
  description = "The disk size in GB for the node pool"
  type        = number
}

variable "swap_enabled" {
  description = "Whether to enable swap on the local NVMe disks."
  type        = bool
}

variable "enable_azure_monitor" {
  description = "Whether to enable Azure Monitor"
  type        = bool
}

variable "log_analytics_workspace_id" {
  description = "The Log Analytics workspace ID"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
}

