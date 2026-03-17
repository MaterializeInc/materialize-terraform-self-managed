# =============================================================================
# Required Variables
# =============================================================================

variable "project_id" {
  description = "The GCP project ID where resources are deployed."
  type        = string
}

variable "region" {
  description = "The GCP region where resources are deployed."
  type        = string
  default     = "us-central1"
}

variable "prefix" {
  description = "Prefix used for all resource names. Must match your existing deployment."
  type        = string
  default     = "materialize"
}

variable "license_key" {
  description = "Materialize license key."
  type        = string
  sensitive   = true
  default     = null
}

variable "database_password" {
  description = "Password for the PostgreSQL database user. Must match your existing database password."
  type        = string
  sensitive   = true
}

variable "external_login_password_mz_system" {
  description = "Password for the mz_system user. Required if authenticator_kind is 'Password' or 'Sasl'."
  type        = string
  sensitive   = true
  default     = null
}

variable "materialize_instance_name" {
  description = "Name of the Materialize instance. Run: kubectl get materialize -A -o jsonpath='{.items[0].metadata.name}'"
  type        = string
}

variable "materialize_instance_namespace" {
  description = "Namespace of the Materialize instance. Run: kubectl get materialize -A -o jsonpath='{.items[0].metadata.namespace}'"
  type        = string
}

# =============================================================================
# Network Configuration
# =============================================================================

variable "subnet_cidr" {
  description = "Primary CIDR range for the GKE subnet."
  type        = string
  default     = "10.0.0.0/20"
}

variable "pods_cidr" {
  description = "Secondary CIDR range for GKE pods."
  type        = string
  default     = "10.48.0.0/14"
}

variable "services_cidr" {
  description = "Secondary CIDR range for GKE services."
  type        = string
  default     = "10.52.0.0/20"
}

# =============================================================================
# GKE Configuration
# =============================================================================

variable "system_node_pool_node_count" {
  description = "Number of nodes in the system node pool."
  type        = number
  default     = 1
}

variable "system_node_pool_machine_type" {
  description = "Machine type for system node pool."
  type        = string
  default     = "n2-highmem-8"
}

variable "system_node_pool_disk_size_gb" {
  description = "Disk size in GB for system node pool."
  type        = number
  default     = 100
}

variable "system_node_pool_min_nodes" {
  description = "Minimum number of system nodes."
  type        = number
  default     = 1
}

variable "system_node_pool_max_nodes" {
  description = "Maximum number of system nodes."
  type        = number
  default     = 2
}

# =============================================================================
# Materialize Nodepool Configuration
# =============================================================================

variable "materialize_node_pool_min_nodes" {
  description = "Minimum number of Materialize worker nodes."
  type        = number
  default     = 1
}

variable "materialize_node_pool_max_nodes" {
  description = "Maximum number of Materialize worker nodes."
  type        = number
  default     = 2
}

variable "materialize_node_pool_machine_type" {
  description = "Machine type for Materialize worker nodes."
  type        = string
  default     = "n2-highmem-8"
}

variable "materialize_node_pool_disk_size_gb" {
  description = "Disk size in GB for Materialize worker nodes."
  type        = number
  default     = 100
}

variable "materialize_node_pool_local_ssd_count" {
  description = "Number of local NVMe SSDs per Materialize node. Each disk is 375GB in GCP."
  type        = number
  default     = 1
}

# =============================================================================
# Database Configuration
# =============================================================================

variable "database_tier" {
  description = "Cloud SQL machine tier."
  type        = string
  default     = "db-custom-2-4096"
}

variable "database_version" {
  description = "PostgreSQL version for Cloud SQL."
  type        = string
  default     = "POSTGRES_15"
}

variable "database_username" {
  description = "Database username."
  type        = string
  default     = "materialize"
}

variable "database_name" {
  description = "Database name."
  type        = string
  default     = "materialize"
}

variable "database_vpc_wait_duration" {
  description = "Duration to wait after VPC setup before creating the database."
  type        = string
  default     = "60s"
}

# =============================================================================
# Operator & Instance Configuration
# =============================================================================

variable "namespace" {
  description = "Kubernetes namespace for the Materialize operator."
  type        = string
  default     = "materialize"
}

variable "operator_version" {
  description = "Version of the Materialize operator to install. Defaults to the module's built-in version."
  type        = string
  default     = null
}

variable "environmentd_version" {
  description = "Version tag of environmentd (e.g., 'v0.130.0'). The module prepends 'materialize/environmentd:'. If not set, defaults to the module's built-in version which may not match your current deployment."
  type        = string
  default     = null
}

variable "authenticator_kind" {
  description = "Kind of authenticator to use for Materialize instance."
  type        = string
  default     = "None"
}

# =============================================================================
# Storage Configuration
# =============================================================================

variable "storage_bucket_versioning" {
  description = "Enable bucket versioning."
  type        = bool
  default     = false
}

variable "storage_bucket_version_ttl" {
  description = "TTL in days for non-current storage bucket objects."
  type        = number
  default     = 7
}

# =============================================================================
# TLS & Cert-Manager Configuration
# =============================================================================

variable "use_self_signed_cluster_issuer" {
  description = "Whether to use a self-signed ClusterIssuer for TLS."
  type        = bool
  default     = true
}

variable "cert_manager_chart_version" {
  description = "cert-manager Helm chart version. Default matches old module's version to avoid unintended upgrades."
  type        = string
  default     = "v1.17.1"
}

# =============================================================================
# Load Balancer Configuration
# =============================================================================

variable "internal_load_balancer" {
  description = "Whether to use internal load balancers."
  type        = bool
  default     = true
}

variable "ingress_cidr_blocks" {
  description = "CIDR blocks allowed to reach external load balancers. Required when internal_load_balancer is false."
  type        = list(string)
  default     = null
}

# =============================================================================
# Labels
# =============================================================================

variable "labels" {
  description = "Labels to apply to all resources."
  type        = map(string)
  default     = {}
}
