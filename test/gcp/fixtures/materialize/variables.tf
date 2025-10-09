# Common variables
variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "labels" {
  description = "Labels to apply to resources created."
  type        = map(string)
}

# Network variables
variable "network_name" {
  description = "Network name from network stage"
  type        = string
}

variable "subnet_name" {
  description = "Subnet name from network stage"
  type        = string
}

variable "network_id" {
  description = "Network ID from network stage"
  type        = string
}

# GKE variables
variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}


variable "materialize_node_type" {
  description = "Node type for Materialize"
  type        = string
}

variable "local_ssd_count" {
  description = "Number of local SSDs to attach"
  type        = number
}

variable "enable_private_nodes" {
  description = "Enable private nodes or not"
  type        = bool
}

variable "swap_enabled" {
  description = "Enable swap"
  type        = bool
}

variable "disk_size" {
  description = "Disk size in GB for nodepool"
  type        = number
}

variable "min_nodes" {
  description = "Min no of nodes in nodepool"
  type        = number
}

variable "max_nodes" {
  description = "Max no of nodes in nodepool"
  type        = number
}

# Database variables
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

# Storage variables
variable "storage_bucket_versioning" {
  description = "Enable versioning for storage bucket"
  type        = bool
}

variable "storage_bucket_version_ttl" {
  description = "TTL for storage bucket versions in days"
  type        = number
}


# Cert Manager variables
variable "cert_manager_install_timeout" {
  description = "Cert-manager install timeout in seconds"
  type        = number
}

variable "cert_manager_chart_version" {
  description = "Cert-manager chart version"
  type        = string
}

variable "cert_manager_namespace" {
  description = "Cert-manager namespace"
  type        = string
}

# Operator variables
variable "operator_namespace" {
  description = "Materialize operator namespace"
  type        = string
}

# Materialize Instance variables
variable "install_materialize_instance" {
  description = "Whether to install the Materialize instance"
  type        = bool
}

variable "instance_name" {
  description = "Name of the Materialize instance"
  type        = string
}

variable "instance_namespace" {
  description = "Namespace for the Materialize instance"
  type        = string
  default     = "materialize-environment"
}


variable "user" {
  description = "User for metadata storage"
  type = object({
    name     = string
    password = string
  })
}

variable "external_login_password_mz_system" {
  description = "Password for external login to Materialize instance"
  type        = string
  sensitive   = true
}

variable "license_key" {
  description = "Materialize license key"
  type        = string
  default     = null
  sensitive   = true
}
