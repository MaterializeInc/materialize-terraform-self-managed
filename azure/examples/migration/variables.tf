# =============================================================================
# Migration Reference Variables
# =============================================================================
#
# Update these variables to match your existing infrastructure.
# Set values in terraform.tfvars (see terraform.tfvars.example).
#
# =============================================================================

# -----------------------------------------------------------------------------
# Azure Configuration
# -----------------------------------------------------------------------------

variable "subscription_id" {
  description = "Azure subscription ID where resources exist"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the existing resource group (must match existing)"
  type        = string
}

variable "location" {
  description = "Azure region where resources exist (must match existing)"
  type        = string
  default     = "eastus2"
}

variable "tags" {
  description = "Tags to apply to resources (should match existing tags)"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Core Configuration
# -----------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix used for all resource names (must match existing)"
  type        = string
  validation {
    condition     = length(var.name_prefix) >= 3 && length(var.name_prefix) <= 16 && can(regex("^[a-z0-9-]+$", var.name_prefix))
    error_message = "Prefix must be between 3-16 characters, lowercase alphanumeric and hyphens only."
  }
}

variable "license_key" {
  description = "Materialize license key"
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Materialize Instance Configuration
# -----------------------------------------------------------------------------

variable "materialize_instance_name" {
  description = "Name of your existing Materialize instance. Run: kubectl get materialize -A"
  type        = string
}

variable "materialize_instance_namespace" {
  description = "Kubernetes namespace for the Materialize instance"
  type        = string
  default     = "materialize-environment"
}

variable "environmentd_version" {
  description = "Materialize environmentd version tag. Must match your existing version. Run: kubectl get materialize -A -o jsonpath='{.items[0].spec.environmentdImageRef}' and extract the tag (e.g., v0.130.0)."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Migration Secrets
# -----------------------------------------------------------------------------

variable "old_db_password" {
  description = "Existing database password from your old configuration"
  type        = string
  sensitive   = true
}

variable "external_login_password_mz_system" {
  description = "Password for mz_system user from your old configuration"
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

variable "vnet_address_space" {
  description = "VNet address space (must match existing)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "aks_subnet_cidr" {
  description = "CIDR for the AKS subnet (must match existing)"
  type        = string
  default     = "10.0.0.0/20"
}

variable "postgres_subnet_cidr" {
  description = "CIDR for the PostgreSQL subnet (must match existing)"
  type        = string
  default     = "10.0.16.0/24"
}

variable "service_cidr" {
  description = "Kubernetes service CIDR (must match existing AKS cluster)"
  type        = string
  default     = "10.1.0.0/16"
}

# -----------------------------------------------------------------------------
# AKS Cluster
# -----------------------------------------------------------------------------

variable "kubernetes_version" {
  description = "Kubernetes version for AKS cluster (must match existing). Run: az aks show --name <prefix>-aks --resource-group <rg> --query kubernetesVersion"
  type        = string
  default     = null
}

variable "default_node_pool_vm_size" {
  description = "VM size for the AKS default node pool (must match existing)"
  type        = string
  default     = "Standard_D2s_v3"
}

# -----------------------------------------------------------------------------
# System Node Pool (from old AKS module)
# -----------------------------------------------------------------------------

variable "system_node_pool_vm_size" {
  description = "VM size for the system node pool (old default: Standard_D2ps_v6)"
  type        = string
  default     = "Standard_D2ps_v6"
}

variable "system_node_pool_disk_size_gb" {
  description = "Disk size in GB for system node pool"
  type        = number
  default     = 100
}

variable "system_node_pool_min_nodes" {
  description = "Minimum nodes in system node pool (old default: 2)"
  type        = number
  default     = 2
}

variable "system_node_pool_max_nodes" {
  description = "Maximum nodes in system node pool (old default: 4)"
  type        = number
  default     = 4
}

# -----------------------------------------------------------------------------
# Materialize Node Pool
# -----------------------------------------------------------------------------

variable "materialize_node_pool_vm_size" {
  description = "VM size for Materialize node pool (old default: Standard_E4pds_v6)"
  type        = string
  default     = "Standard_E4pds_v6"
}

variable "materialize_node_pool_disk_size_gb" {
  description = "Disk size in GB for Materialize node pool"
  type        = number
  default     = 100
}

variable "materialize_node_pool_min_nodes" {
  description = "Minimum nodes in Materialize node pool (old default: 1)"
  type        = number
  default     = 1
}

variable "materialize_node_pool_max_nodes" {
  description = "Maximum nodes in Materialize node pool (old default: 4)"
  type        = number
  default     = 4
}

# -----------------------------------------------------------------------------
# Database (PostgreSQL Flexible Server)
# -----------------------------------------------------------------------------

variable "database_username" {
  description = "PostgreSQL administrator login (must match existing)"
  type        = string
  default     = "materialize"
}

variable "database_name" {
  description = "PostgreSQL database name (must match existing)"
  type        = string
  default     = "materialize"
}

variable "postgres_version" {
  description = "PostgreSQL version (must match existing)"
  type        = string
  default     = "15"
}

variable "database_sku_name" {
  description = "SKU name for PostgreSQL Flexible Server (must match existing)"
  type        = string
  default     = "GP_Standard_D2s_v3"
}

variable "database_storage_mb" {
  description = "Storage in MB for PostgreSQL (must match existing)"
  type        = number
  default     = 32768
}

# -----------------------------------------------------------------------------
# TLS Configuration
# -----------------------------------------------------------------------------

variable "use_self_signed_cluster_issuer" {
  description = "Whether to enable TLS using the self-signed cluster issuer. Must match your old module's setting."
  type        = bool
  default     = true
}

variable "cert_manager_chart_version" {
  description = "cert-manager Helm chart version. Default matches old module's version to avoid unintended upgrades."
  type        = string
  default     = "v1.17.1"
}

# -----------------------------------------------------------------------------
# Access Control
# -----------------------------------------------------------------------------

variable "ingress_cidr_blocks" {
  description = "List of CIDR blocks to allow access to Materialize load balancers"
  type        = list(string)
  default     = null
  nullable    = true
}

variable "internal_load_balancer" {
  description = "Whether to use an internal load balancer"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Operator Configuration
# -----------------------------------------------------------------------------

variable "operator_version" {
  description = "Materialize operator Helm chart version. Must match your existing operator version to avoid unintended upgrades/downgrades. Run: helm list -n materialize -o json | jq -r '.[0].chart' to find current version."
  type        = string
  default     = null
}

variable "disk_setup_image" {
  description = "Docker image for the disk setup daemonset. Old module default: v0.4.0. Set to match your existing daemonset to avoid unnecessary updates. Run: kubectl get daemonset disk-setup -n disk-setup -o jsonpath='{.spec.template.spec.initContainers[0].image}'"
  type        = string
  default     = "materialize/ephemeral-storage-setup-image:v0.4.0"
}

# -----------------------------------------------------------------------------
# Rollout Configuration (usually leave as defaults)
# -----------------------------------------------------------------------------

variable "force_rollout" {
  description = "UUID to force a rollout"
  type        = string
  default     = "00000000-0000-0000-0000-000000000003"
}

variable "request_rollout" {
  description = "UUID to request a rollout"
  type        = string
  default     = "00000000-0000-0000-0000-000000000003"
}
