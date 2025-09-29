variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "network_id" {
  description = "Network ID from network stage"
  type        = string
}

variable "prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "database_tier" {
  description = "CloudSQL tier"
  type        = string
}

variable "db_version" {
  description = "PostgreSQL version"
  type        = string
}

variable "databases" {
  description = "List of databases to create"
  type = list(object({
    name      = string
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.UTF8")
  }))
}

variable "users" {
  description = "List of users to create"
  type = list(object({
    name     = string
    password = optional(string, null)
  }))
  validation {
    condition     = length(var.users) > 0
    error_message = "At least one user is required"
  }
}

variable "labels" {
  description = "Labels to apply to resources created."
  type        = map(string)
}
