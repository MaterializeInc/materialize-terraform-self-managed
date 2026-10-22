variable "name" {
  description = "Name of the Karpenter NodePool and AKSNodeClass."
  type        = string
  nullable    = false
}

variable "location" {
  description = "Azure region of the AKS cluster. Used to build zone labels from `zones`."
  type        = string
  nullable    = false
}

variable "vm_sizes" {
  description = "VM sizes Node Auto Provisioning may create, e.g. [\"Standard_E4pds_v6\"]. For swap, use sizes with local NVMe disks."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.vm_sizes) > 0
    error_message = "vm_sizes must contain at least one VM size."
  }
}

variable "os_disk_size_gb" {
  description = "Size of each node's managed OS disk in GB."
  type        = number
  default     = 100
  nullable    = false

  validation {
    condition     = var.os_disk_size_gb >= 30 && var.os_disk_size_gb <= 2048
    error_message = "os_disk_size_gb must be between 30 and 2048."
  }
}

variable "zones" {
  description = "Availability zones (\"1\", \"2\", \"3\") to provision nodes in. When null, Node Auto Provisioning chooses."
  type        = list(string)
  default     = null

  validation {
    condition = var.zones == null ? true : length(var.zones) > 0 && alltrue([
      for zone in var.zones : contains(["1", "2", "3"], zone)
    ])
    error_message = "zones must be null or a non-empty list of \"1\", \"2\", or \"3\"."
  }
}

variable "node_labels" {
  description = "Labels to apply to created Kubernetes nodes."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "node_taints" {
  description = "Taints to apply to created Kubernetes nodes."
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default  = []
  nullable = false
}

variable "tags" {
  description = "Azure tags to apply to the VMs."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "disruption" {
  description = "Configuration for node disruption."
  type        = any
  default = {
    "budgets" : [
      {
        "nodes" : "10%",
      },
    ],
    "consolidateAfter" : "60s",
    "consolidationPolicy" : "WhenEmpty",
  }
}

variable "expire_after" {
  description = "Time after which the node will expire."
  type        = string
  default     = "Never"
}

variable "termination_grace_period" {
  description = <<-EOT
    Maximum time Karpenter will wait for pods to drain before forcefully
    terminating a node, e.g. "300s". When set, Karpenter will disrupt nodes
    (e.g. on drift after a VM size change) even if they run pods with
    the karpenter.sh/do-not-disrupt annotation or blocking PDBs. Leave null
    so that do-not-disrupt pods (such as Materialize instance pods) block
    disruption until they are removed by a Materialize rollout.
  EOT
  type        = string
  default     = null
}

variable "limits" {
  description = <<-EOT
    Resource limits for the NodePool, e.g. { cpu = "1000" }. Karpenter stops
    provisioning new nodes from this pool once the total resources of its
    nodes reach these limits; existing nodes are unaffected. Setting
    { cpu = "0" } prevents the pool from provisioning any new nodes.
  EOT
  type        = map(string)
  default     = null
}

# Disk setup variables
variable "swap_enabled" {
  description = "Whether to enable swap on the local NVMe disks."
  type        = bool
  default     = false
  nullable    = false
}

variable "disk_setup_name" {
  description = "Name used for disk setup Kubernetes resources (namespace, daemonset, service account, cluster role, cluster role binding). Defaults to \"<name>-disk-setup\"."
  type        = string
  default     = null
}

variable "disk_setup_image" {
  description = "Docker image for the disk setup script"
  type        = string
  default     = "materialize/ephemeral-storage-setup-image:v0.5.1"
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
