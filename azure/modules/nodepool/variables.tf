variable "prefix" {
  description = "Prefix to be used for resource names"
  type        = string
  nullable    = false
}

variable "cluster_id" {
  description = "The ID of the AKS cluster"
  type        = string
  nullable    = false
}

variable "subnet_id" {
  description = "The ID of the subnet"
  type        = string
  nullable    = false
}

variable "vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  # Ask team for suitable default here.
  nullable = false
}

variable "disk_size_gb" {
  description = "Size of the disk attached to each node"
  type        = number
  # Ask team for suitable default here.
  nullable = false
}

variable "autoscaling_config" {
  description = "Auto-scaling configuration for the node pool"
  type = object({
    enabled    = bool
    min_nodes  = optional(number)
    max_nodes  = optional(number)
    node_count = optional(number)
  })
  default = {
    enabled    = true
    min_nodes  = 1
    max_nodes  = 10
    node_count = null
  }
  nullable = false
  validation {
    condition = (
      !var.autoscaling_config.enabled || (
        var.autoscaling_config.min_nodes != null &&
        var.autoscaling_config.max_nodes != null &&
        try(var.autoscaling_config.min_nodes > 0, false) &&
        try(var.autoscaling_config.min_nodes <= var.autoscaling_config.max_nodes, false)
      )
    )
    error_message = "When autoscaling is enabled, min_nodes and max_nodes must be provided, min_nodes must be > 0, and min_nodes must be <= max_nodes."
  }

  validation {
    condition = (
      var.autoscaling_config.enabled || (
        var.autoscaling_config.node_count != null &&
        try(var.autoscaling_config.node_count > 0, false)
      )
    )
    error_message = "When autoscaling is disabled, node_count must be provided and must be > 0."
  }
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "zones" {
  description = "List of availability zones for the node pool. Azure supports zones 1, 2, and 3. When null (the default), Azure distributes nodes without zone pinning. Set to [\"1\", \"2\", \"3\"] for production HA."
  type        = list(string)
  default     = null
  nullable    = true

  validation {
    condition     = var.zones == null ? true : length(var.zones) > 0
    error_message = "zones cannot be an empty list. Use null to let Azure choose."
  }

  validation {
    condition = var.zones == null ? true : alltrue([
      for zone in var.zones :
      contains(["1", "2", "3"], zone)
    ])
    error_message = "Zones must be \"1\", \"2\", or \"3\"."
  }
}

variable "labels" {
  description = "Additional labels to apply to Kubernetes resources"
  type        = map(string)
  default     = {}
}

# https://github.com/Azure/AKS/issues/2934
variable "node_taints" {
  description = "Taints to apply to the node pool. Note: Once applied via Terraform, these taints cannot be manually removed by users due to AKS webhook restrictions."
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = []
}

# Disk setup variables
variable "swap_enabled" {
  description = "Whether to enable swap on the local NVMe disks."
  type        = bool
  default     = false
  nullable    = false
}

variable "disk_setup_name" {
  description = "Name used for disk setup Kubernetes resources (namespace, daemonset, service account, cluster role, cluster role binding)"
  type        = string
  default     = "disk-setup"
  nullable    = false
}

variable "disk_setup_image" {
  description = "Docker image for the disk setup script"
  type        = string
  default     = "materialize/ephemeral-storage-setup-image:v0.4.1"
  nullable    = false
}

variable "disk_setup_container_resource_config" {
  description = "Resource configuration for disk setup init container"
  type = object({
    memory_limit   = string
    memory_request = string
    cpu_request    = string
  })
  default = {
    memory_limit   = "128Mi"
    memory_request = "128Mi"
    cpu_request    = "50m"
  }
  nullable = false
}

variable "pause_container_resource_config" {
  description = "Resource configuration for pause container"
  type = object({
    memory_limit   = string
    memory_request = string
    cpu_request    = string
  })
  default = {
    memory_limit   = "8Mi"
    memory_request = "8Mi"
    cpu_request    = "1m"
  }
  nullable = false
}
