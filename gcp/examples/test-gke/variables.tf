variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "network_name" {
  description = "Network name from network stage"
  type        = string
}

variable "subnet_name" {
  description = "Subnet name from network stage"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "skip_nodepool" {
  description = "Skip nodepool creation"
  type        = bool
}

variable "materialize_node_type" {
  description = "Node type for Materialize"
  type        = string
}

variable "local_ssd_count" {
  description = "Number of local SSDs to attach"
  type        = number
}

variable "enable_private_nodes" {
  description = "Enable private nodes or not"
  type        = bool
}

variable "swap_enabled" {
  description = "Enable swap"
  type        = bool
}

variable "disk_size" {
  description = "Disk size in GB for nodepool"
  type        = number
}

variable "min_nodes" {
  description = "Min no of nodes in nodepool"
  type        = number
}

variable "max_nodes" {
  description = "Max no of nodes in nodepool"
  type        = number
}

variable "labels" {
  description = "Labels to apply to resources created."
  type        = map(string)
}
