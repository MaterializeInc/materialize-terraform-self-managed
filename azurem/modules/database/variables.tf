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
    error_message = "Version must be a number (e.g., 15)"
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
