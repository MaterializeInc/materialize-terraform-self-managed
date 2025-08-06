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
  default     = "test"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

// TODO fix this
variable "database_tier" {
  description = "CloudSQL tier"
  type        = string
  default     = "db-custom-2-4096"
}

variable "db_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "POSTGRES_15"
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
    password = string
  }))
}
