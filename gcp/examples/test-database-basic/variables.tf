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

variable "database_password" {
  description = "Database password"
  type        = string
  sensitive   = true
  default     = "test-password-123!"
}

variable "database_name" {
  description = "Name of database to create"
  type        = string
  default     = "materialize-test"
}

variable "user_name" {
  description = "UserName for the database that is created"
  type        = string
  default     = "materialize-test"
}
