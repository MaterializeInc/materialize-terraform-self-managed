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
  default     = "materialize"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "skip_nodepool" {
  description = "Skip nodepool creation"
  type        = bool
  default     = false
}

variable "materialize_node_count" {
  description = "Number of nodes for Materialize"
  type        = number
  default     = 1
}

variable "materialize_node_type" {
  description = "Node type for Materialize"
  type        = string
  default     = "n2-highmem-8"
}


variable "local_ssd_count" {
  description = "Number of local SSDs to attach"
  type        = number
  default     = 0
}

variable "enable_private_nodes" {
  description = "Enable private nodes or not"
  type        = bool
  default     = true
}

variable "disk_setup_enabled" {
  description = "Enable disk setup or not"
  type        = bool
  default     = false
}

variable "disk_size" {
  description = "Disk size in GB for nodepool"
  type        = number
  default     = 50
}

variable "min_nodes" {
  description = "Min no of nodes in nodepool"
  type        = number
  default     = 1
}

variable "max_nodes" {
  description = "Max no of nodes in nodepool"
  type        = number
  default     = 3
}
