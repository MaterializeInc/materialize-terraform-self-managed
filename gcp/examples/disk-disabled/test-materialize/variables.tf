variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "us-east1"
}

variable "prefix" {
  description = "Prefix for all resources"
  type        = string
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default     = {}
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
  default     = false
}

variable "storage_bucket_version_ttl" {
  description = "TTL for storage bucket versions in days"
  type        = number
  default     = 7
}

# Certificate configuration
variable "install_cert_manager" {
  description = "Install cert-manager"
  type        = bool
  default     = true
}

variable "cert_manager_install_timeout" {
  description = "Cert-manager install timeout in seconds"
  type        = number
  default     = 600
}

variable "cert_manager_chart_version" {
  description = "Cert-manager chart version"
  type        = string
  default     = "v1.17.1"
}

variable "cert_manager_namespace" {
  description = "Cert-manager namespace"
  type        = string
  default     = "cert-manager"
}

# OpenEBS configuration
variable "install_openebs" {
  description = "Install OpenEBS for disk-based storage"
  type        = bool
  default     = false
}

variable "openebs_namespace" {
  description = "OpenEBS namespace"
  type        = string
  default     = "openebs"
}

variable "openebs_chart_version" {
  description = "OpenEBS chart version"
  type        = string
  default     = "4.2.0"
}

# Materialize operator configuration
variable "install_materialize_operator" {
  description = "Whether to install the Materialize operator"
  type        = bool
  default     = true
}

variable "operator_namespace" {
  description = "Materialize operator namespace"
  type        = string
  default     = "materialize"
}

# Materialize instance configuration
variable "install_materialize_instance" {
  description = "Whether to install the Materialize instance"
  type        = bool
  default     = false
}

variable "instance_name" {
  description = "Name of the Materialize instance"
  type        = string
  default     = "main"
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
  default     = "materialize"
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

variable "disk_setup_enabled" {
  description = "Enable disk setup or not"
  type        = bool
  default     = false
}
