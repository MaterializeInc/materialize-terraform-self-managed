variable "prefix" {
  description = "Prefix to be used for resource names"
  type        = string
}

variable "cluster_id" {
  description = "The ID of the AKS cluster"
  type        = string
}

variable "subnet_id" {
  description = "The ID of the subnet"
  type        = string
}

variable "vm_size" {
  description = "VM size for AKS nodes"
  type        = string
}

variable "disk_size_gb" {
  description = "Size of the disk attached to each node"
  type        = number
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

variable "labels" {
  description = "Additional labels to apply to Kubernetes resources"
  type        = map(string)
  default     = {}
}

# Disk setup variables
variable "enable_disk_setup" {
  description = "Whether to enable the local NVMe SSD disks setup script"
  type        = bool
  default     = false
}

variable "disk_setup_image" {
  description = "Docker image for the disk setup script"
  type        = string
  default     = "materialize/ephemeral-storage-setup-image:v0.1.2"
}

variable "pause_container_image" {
  description = "Image for the pause container"
  type        = string
  default     = "mcr.microsoft.com/oss/kubernetes/pause:3.6"
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
}
