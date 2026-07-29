variable "create_storage_class" {
  description = "Whether to create the storage class. Set to false if using GKE's default 'standard-rwo' class which already has WaitForFirstConsumer."
  type        = bool
  default     = true
  nullable    = false
}

variable "storage_class_name" {
  description = "Name of the Kubernetes StorageClass to create"
  type        = string
  default     = "pd-ssd"
  nullable    = false
}

variable "disk_type" {
  description = <<-EOT
    Type of GCP Persistent Disk:
    - pd-standard: HDD, lowest cost, suitable for batch workloads
    - pd-balanced: Balanced SSD, good price/performance ratio (default for standard-rwo)
    - pd-ssd: SSD, higher performance than pd-balanced
    - pd-extreme: Highest performance SSD, requires provisioned IOPS and minimum 500GB size

    Note: pd-extreme disks have additional requirements and higher costs.
    See https://cloud.google.com/compute/docs/disks/extreme-persistent-disk
  EOT
  type        = string
  default     = "pd-ssd"
  nullable    = false

  validation {
    condition     = contains(["pd-standard", "pd-ssd", "pd-balanced", "pd-extreme"], var.disk_type)
    error_message = "disk_type must be one of: pd-standard, pd-ssd, pd-balanced, pd-extreme"
  }
}

variable "reclaim_policy" {
  description = "Reclaim policy for persistent volumes. Options: Delete, Retain"
  type        = string
  default     = "Delete"
  nullable    = false

  validation {
    condition     = contains(["Delete", "Retain"], var.reclaim_policy)
    error_message = "reclaim_policy must be either 'Delete' or 'Retain'"
  }
}

variable "allow_volume_expansion" {
  description = "Whether to allow volume expansion after creation"
  type        = bool
  default     = true
  nullable    = false
}

variable "set_as_default" {
  description = "Whether to set this storage class as the cluster default"
  type        = bool
  default     = false
  nullable    = false
}

variable "replication_type" {
  description = "Replication type for the disk. Options: none (zonal), regional-pd (regional). Regional PDs replicate data across two zones for higher availability but cost more."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.replication_type == null || contains(["none", "regional-pd"], var.replication_type)
    error_message = "replication_type must be null, 'none', or 'regional-pd'"
  }
}
