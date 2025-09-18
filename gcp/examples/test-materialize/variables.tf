variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
}

variable "prefix" {
  description = "Prefix for all resources"
  type        = string
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
}

variable "cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  type        = string
}

variable "cluster_endpoint" {
  description = "GKE cluster endpoint"
  type        = string
}

# Storage configuration
variable "workload_identity_sa_email" {
  description = "Workload identity service account email"
  type        = string
}


variable "storage_bucket_versioning" {
  description = "Enable versioning for storage bucket"
  type        = bool
}

variable "storage_bucket_version_ttl" {
  description = "TTL for storage bucket versions in days"
  type        = number
}

# Certificate configuration
variable "install_cert_manager" {
  description = "Install cert-manager"
  type        = bool
}

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

variable "operator_namespace" {
  description = "Materialize operator namespace"
  type        = string
}

# Materialize instance configuration
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

# Database configuration
variable "database_host" {
  description = "Database host for metadata storage"
  type        = string
}

variable "database_name" {
  description = "Database name for metadata storage"
  type        = string
}

variable "user" {
  description = "User for metadata storage"
  type = object({
    name     = string
    password = string
  })
}

# Materialize instance authentication
variable "external_login_password" {
  description = "Password for external login to Materialize instance"
  type        = string
  sensitive   = true
}

variable "swap_enabled" {
  description = "Enable swap"
  type        = bool
}
