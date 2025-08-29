variable "subscription_id" {
  description = "The ID of the Azure subscription"
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group"
  type        = string
}

variable "location" {
  description = "The location of the Azure subscription"
  type        = string
  # default     = "westus2"
}

variable "prefix" {
  description = "The prefix for resource naming"
  type        = string
}

variable "subnet_id" {
  description = "The ID of the subnet for the database"
  type        = string
}

variable "private_dns_zone_id" {
  description = "The ID of the private DNS zone"
  type        = string
}

variable "databases" {
  description = "List of databases to create"
  type = list(object({
    name      = string
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.utf8")
  }))
}

variable "administrator_login" {
  description = "The administrator login for the database server"
  type        = string
  # default     = "materialize"
}

variable "administrator_password" {
  description = "The administrator password for the database server"
  type        = string
  # default     = "materialize"
}

variable "sku_name" {
  description = "The SKU name for the database server"
  type        = string
  # default     = "GP_Standard_D2s_v3"
}

variable "postgres_version" {
  description = "The PostgreSQL version"
  type        = string
  # default     = "15"
}

variable "storage_mb" {
  description = "The storage size in MB"
  type        = number
  # default     = 32768
}

variable "backup_retention_days" {
  description = "The backup retention period in days"
  type        = number
  # default     = 7
}

variable "public_network_access_enabled" {
  description = "Whether public network access is enabled"
  type        = bool
  # default     = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  # default = {
  #   Environment = "test"
  #   Project     = "materialize"
  # }
}

