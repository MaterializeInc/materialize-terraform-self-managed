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
  # default     = "westus2"
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
  # default     = "1.32"
}

variable "service_cidr" {
  description = "The service CIDR for the AKS cluster"
  type        = string
  # default     = "10.101.0.0/16"
}

variable "default_node_pool_vm_size" {
  description = "The VM size for the default node pool"
  type        = string
  # default     = "Standard_D2s_v3"
}

variable "default_node_pool_node_count" {
  description = "The node count for the default node pool"
  type        = number
  # default     = 2
}

variable "nodepool_vm_size" {
  description = "The VM size for the Materialize node pool"
  type        = string
  # default     = "Standard_E4pds_v6"
}

variable "auto_scaling_enabled" {
  description = "Whether auto scaling is enabled for the node pool"
  type        = bool
  # default     = true
}

variable "min_nodes" {
  description = "The minimum number of nodes in the node pool"
  type        = number
  # default     = 1
}

variable "max_nodes" {
  description = "The maximum number of nodes in the node pool"
  type        = number
  # default     = 5
}

variable "node_count" {
  description = "The initial node count for the node pool"
  type        = number
  # default     = 2
}

variable "disk_size_gb" {
  description = "The disk size in GB for the node pool"
  type        = number
  # default     = 100
}

variable "enable_disk_setup" {
  description = "Whether to enable disk setup for the node pool"
  type        = bool
}

variable "disk_setup_image" {
  description = "The disk setup image for the node pool"
  type        = string
  # default     = "materialize/ephemeral-storage-setup-image:v0.1.1"
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

