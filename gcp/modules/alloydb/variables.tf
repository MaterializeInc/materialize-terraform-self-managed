variable "project_id" {
  description = "The ID of the project where resources will be created"
  type        = string
  nullable    = false
}

variable "region" {
  description = "The region where resources will be created"
  type        = string
  nullable    = false
}

variable "prefix" {
  description = "Prefix to be used for resource names"
  type        = string
  nullable    = false
}

variable "network_id" {
  description = "The ID of the VPC network to connect the database to"
  type        = string
  nullable    = false
}

variable "database_version" {
  description = "The PostgreSQL major version for the AlloyDB cluster"
  type        = string
  default     = "POSTGRES_15"
  validation {
    condition     = can(regex("^POSTGRES_(14|15|16)$", var.database_version))
    error_message = "Version must be POSTGRES_14, POSTGRES_15, or POSTGRES_16"
  }
}

variable "cluster_type" {
  description = "The type of AlloyDB cluster (PRIMARY or SECONDARY)"
  type        = string
  default     = "PRIMARY"
  validation {
    condition     = contains(["PRIMARY", "SECONDARY"], var.cluster_type)
    error_message = "cluster_type must be PRIMARY or SECONDARY"
  }
}

variable "databases" {
  description = "List of databases to create (note: AlloyDB creates 'postgres' db by default)"
  type = list(object({
    name      = string
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.UTF8")
  }))
  default = []
}

variable "users" {
  description = "List of users to create"
  type = list(object({
    name     = string
    password = optional(string, null)
  }))
  validation {
    condition     = length(var.users) > 0
    error_message = "At least one user must be specified."
  }
}

variable "labels" {
  description = "Labels to apply to AlloyDB resources"
  type        = map(string)
  default     = {}
}

# Primary instance configuration
variable "cpu_count" {
  description = "The number of CPUs for the primary instance (2, 4, 8, 16, 32, 64, 96, or 128)"
  type        = number
  default     = 2
  validation {
    condition     = contains([2, 4, 8, 16, 32, 64, 96, 128], var.cpu_count)
    error_message = "cpu_count must be one of: 2, 4, 8, 16, 32, 64, 96, 128"
  }
}

variable "machine_type" {
  description = "The machine type for the primary instance. If not set, uses default based on cpu_count."
  type        = string
  default     = null
}

# Automated backup configuration
variable "automated_backup_enabled" {
  description = "Enable automated backups"
  type        = bool
  default     = true
}

variable "automated_backup_days" {
  description = "Days of the week to perform automated backup (MONDAY, TUESDAY, etc.)"
  type        = list(string)
  default     = ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"]
}

variable "automated_backup_start_hour" {
  description = "Hour of day (0-23) to start automated backup in UTC"
  type        = number
  default     = 3
}

variable "backup_retention_days" {
  description = "Number of days to retain backups (1-365)"
  type        = number
  default     = 14
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "backup_retention_days must be between 1 and 365"
  }
}

# Continuous backup (PITR) configuration
variable "continuous_backup_enabled" {
  description = "Enable continuous backup for point-in-time recovery"
  type        = bool
  default     = true
}

variable "continuous_backup_retention_days" {
  description = "Number of days to retain continuous backups (1-35)"
  type        = number
  default     = 14
  validation {
    condition     = var.continuous_backup_retention_days >= 1 && var.continuous_backup_retention_days <= 35
    error_message = "continuous_backup_retention_days must be between 1 and 35"
  }
}

# Maintenance window
variable "maintenance_window_day" {
  description = "Day of week for maintenance window (MONDAY, TUESDAY, etc.)"
  type        = string
  default     = "SUNDAY"
}

variable "maintenance_window_hour" {
  description = "Hour of day (0-23) for maintenance window start in UTC"
  type        = number
  default     = 3
}

# Deletion protection
variable "deletion_protection" {
  description = "Enable deletion protection for the cluster"
  type        = bool
  default     = false
}

# Database flags
variable "database_flags" {
  description = "Map of database flags to set on the primary instance"
  type        = map(string)
  default     = {}
}

# Query insights configuration
variable "query_insights_enabled" {
  description = "Enable query insights"
  type        = bool
  default     = true
}

variable "query_string_length" {
  description = "Query string length for query insights (256-4500)"
  type        = number
  default     = 1024
}

variable "record_application_tags" {
  description = "Record application tags in query insights"
  type        = bool
  default     = true
}

variable "record_client_address" {
  description = "Record client address in query insights"
  type        = bool
  default     = true
}

variable "query_plans_per_minute" {
  description = "Number of query plans to sample per minute (1-20)"
  type        = number
  default     = 5
}

# Availability
variable "availability_type" {
  description = "Availability type for the primary instance (REGIONAL for HA, ZONAL for single zone)"
  type        = string
  default     = "REGIONAL"
  validation {
    condition     = contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "availability_type must be REGIONAL or ZONAL"
  }
}
