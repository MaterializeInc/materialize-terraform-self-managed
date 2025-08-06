variable "project_id" {
  description = "The ID of the project where resources will be created"
  type        = string
}

variable "region" {
  description = "The region where resources will be created"
  type        = string
}

variable "prefix" {
  description = "Prefix to be used for resource names"
  type        = string
}

variable "network_id" {
  description = "The ID of the VPC network to connect the database to"
  type        = string
}

variable "tier" {
  description = "The machine tier for the database instance"
  type        = string
}

variable "db_version" {
  description = "The PostgreSQL version to use"
  type        = string
  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.db_version))
    error_message = "Version must be in format POSTGRES_XX where XX is the version number"
  }
}

variable "databases" {
  description = "List of additional databases to create"
  type = list(object({
    name      = string
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.UTF8")
  }))
  validation {
    condition     = length(var.databases) > 0
    error_message = "At least one database must be specified."
  }
}

variable "users" {
  description = "List of users to create"
  type = list(object({
    name            = string
    password        = optional(string, null)
    random_password = optional(bool, false)
  }))
  validation {
    condition     = length(var.users) > 0
    error_message = "At least one user must be specified."
  }
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}

# Any change to this variable will be ignored by the module during upgrades
# if you want to set disk size, you need to set this during the first apply
# Reference: https://registry.terraform.io/providers/hashicorp/google/6.34.1/docs/resources/sql_database_instance#disk_size-1
variable "disk_size" {
  description = "The disk size for the database instance in GB"
  type        = number
  default     = null
}

variable "disk_type" {
  description = "The disk type for the database instance"
  type        = string
  default     = "PD_SSD"
}

variable "disk_autoresize" {
  description = "Enable automatic increase of disk size"
  type        = bool
  default     = true
}

variable "disk_autoresize_limit" {
  description = "The maximum size to which storage can be auto increased"
  type        = number
  default     = 0
}

variable "backup_enabled" {
  description = "Enable backup configuration"
  type        = bool
  default     = true
}

variable "backup_start_time" {
  description = "HH:MM format time indicating when backup starts"
  type        = string
  default     = "03:00"
}

variable "point_in_time_recovery_enabled" {
  description = "Enable point in time recovery"
  type        = bool
  default     = true
}

variable "backup_retained_backups" {
  description = "Number of backups to retain"
  type        = number
  default     = 7
}

variable "backup_retention_unit" {
  description = "The unit of time for backup retention"
  type        = string
  default     = "COUNT"
}

variable "maintenance_window_day" {
  description = "Day of week for maintenance window (1-7)"
  type        = number
  default     = 7
}

variable "maintenance_window_hour" {
  description = "Hour of day for maintenance window (0-23)"
  type        = number
  default     = 3
}

variable "maintenance_window_update_track" {
  description = "Maintenance window update track"
  type        = string
  default     = "stable"
}

variable "database_flags" {
  description = "List of database flags to apply to the instance"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "create_timeout" {
  description = "Timeout for create operations"
  type        = string
  default     = "60m"
}

variable "update_timeout" {
  description = "Timeout for update operations"
  type        = string
  default     = "45m"
}

variable "delete_timeout" {
  description = "Timeout for delete operations"
  type        = string
  default     = "45m"
}

variable "database_deletion_policy" {
  description = "Deletion policy for databases"
  type        = string
  default     = "ABANDON"
}

variable "user_deletion_policy" {
  description = "Deletion policy for users"
  type        = string
  default     = "ABANDON"
}
