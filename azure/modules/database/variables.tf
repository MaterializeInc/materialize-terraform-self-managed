variable "resource_group_name" {
  description = "The name of the resource group"
  type        = string
  nullable    = false
}

variable "location" {
  description = "The location where resources will be created"
  type        = string
  nullable    = false
}

variable "prefix" {
  description = "Prefix to be used for resource names"
  type        = string
  nullable    = false
}

variable "subnet_id" {
  description = "The ID of the subnet for PostgreSQL"
  type        = string
  nullable    = false
}

variable "private_dns_zone_id" {
  description = "The ID of the private DNS zone"
  type        = string
  nullable    = false
}

variable "sku_name" {
  description = "The SKU name for the PostgreSQL server, sku denotes the size of postgres server"
  type        = string
  nullable    = false
}

variable "postgres_version" {
  description = "The PostgreSQL version"
  type        = string
  validation {
    condition     = can(regex("^[0-9]+$", var.postgres_version))
    error_message = "Version must be a number (e.g., 18)"
  }
}

variable "administrator_login" {
  description = "The administrator login name for the PostgreSQL server"
  type        = string
  nullable    = false
}

variable "administrator_password" {
  description = "The administrator password for the PostgreSQL server. If not provided, a random password will be generated."
  type        = string
  default     = null
  sensitive   = true
}

variable "databases" {
  description = "List of databases to create"
  type = list(object({
    name      = string
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.utf8")
  }))
  validation {
    condition     = length(var.databases) > 0
    error_message = "At least one database must be specified."
  }
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "storage_mb" {
  description = "The storage capacity in MB"
  type        = number
  # Ask team for suitable default here.
  default  = 32768
  nullable = false
}

variable "storage_type" {
  description = <<-EOT
    The disk type: `Premium_LRS` (Premium SSD) or `PremiumV2_LRS` (Premium SSD v2).

    Premium SSD v2 is usually cheaper for the same performance and lets IOPS and throughput be set
    independently of size, but it needs a General Purpose or Memory Optimized `sku_name` and does
    not support storage autogrow or PostgreSQL 13 or older.

    Changing this on an existing server replaces it, which destroys the Materialize metadata:
    Azure has no online migration between the two. Moving an existing server to Premium SSD v2 is
    not supported; keep Premium_LRS on it.
  EOT
  type        = string
  default     = "Premium_LRS"
  nullable    = false

  validation {
    condition     = contains(["Premium_LRS", "PremiumV2_LRS"], var.storage_type)
    error_message = "storage_type must be Premium_LRS or PremiumV2_LRS."
  }
}

variable "storage_iops" {
  description = "Provisioned IOPS, 3000 to 80000. Required for, and only used with, `storage_type = \"PremiumV2_LRS\"`. Free up to 3000 below 400 GiB of storage, and up to 12000 from 400 GiB."
  type        = number
  default     = null

  validation {
    condition     = var.storage_iops == null || (var.storage_iops >= 3000 && var.storage_iops <= 80000)
    error_message = "storage_iops must be between 3000 and 80000."
  }
}

variable "storage_throughput" {
  description = "Provisioned throughput in MB/s, 125 to 1200. Required for, and only used with, `storage_type = \"PremiumV2_LRS\"`. Free up to 125 MB/s below 400 GiB of storage, and up to 500 MB/s from 400 GiB."
  type        = number
  default     = null

  validation {
    condition     = var.storage_throughput == null || (var.storage_throughput >= 125 && var.storage_throughput <= 1200)
    error_message = "storage_throughput must be between 125 and 1200."
  }
}

variable "backup_retention_days" {
  description = "The number of days to retain backups"
  type        = number
  default     = 7
  nullable    = false
}

variable "public_network_access_enabled" {
  description = "Whether public network access is enabled"
  type        = bool
  default     = false
  nullable    = false
}
