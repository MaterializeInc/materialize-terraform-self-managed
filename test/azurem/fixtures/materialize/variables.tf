# Common variables
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
}

variable "prefix" {
  description = "The prefix for resource naming"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
}

# Network variables
variable "vnet_name" {
  description = "The name of the virtual network"
  type        = string
}

variable "subnet_name" {
  description = "The name of the subnet"
  type        = string
}

variable "subnet_id" {
  description = "The ID of the subnet"
  type        = string
}

variable "database_subnet_id" {
  description = "The ID of the subnet for the database"
  type        = string
}

variable "private_dns_zone_id" {
  description = "The ID of the private DNS zone"
  type        = string
}

# AKS variables
variable "kubernetes_version" {
  description = "The Kubernetes version"
  type        = string
}

variable "service_cidr" {
  description = "The service CIDR for the AKS cluster"
  type        = string
}

variable "default_node_pool_vm_size" {
  description = "The VM size for the default node pool"
  type        = string
}

variable "default_node_pool_enable_auto_scaling" {
  description = "Enable auto scaling for the default node pool"
  type        = bool
}

variable "default_node_pool_node_count" {
  description = "The node count for the default node pool (used only when auto scaling is disabled)"
  type        = number
}

variable "default_node_pool_min_count" {
  description = "Minimum number of nodes in the default node pool (used only when auto scaling is enabled)"
  type        = number
}

variable "default_node_pool_max_count" {
  description = "Maximum number of nodes in the default node pool (used only when auto scaling is enabled)"
  type        = number
}

variable "nodepool_vm_size" {
  description = "The VM size for the Materialize node pool"
  type        = string
}

variable "node_labels" {
  description = "The labels for the node pool"
  type        = map(string)
}

variable "auto_scaling_enabled" {
  description = "Whether auto scaling is enabled for the node pool"
  type        = bool
}

variable "min_nodes" {
  description = "The minimum number of nodes in the node pool"
  type        = number
}

variable "max_nodes" {
  description = "The maximum number of nodes in the node pool"
  type        = number
}

variable "node_count" {
  description = "The initial node count for the node pool"
  type        = number
}

variable "disk_size_gb" {
  description = "The disk size in GB for the node pool"
  type        = number
}

variable "swap_enabled" {
  description = "Whether to enable swap on the local NVMe disks."
  type        = bool
}

variable "enable_azure_monitor" {
  description = "Whether to enable Azure Monitor"
  type        = bool
}

variable "log_analytics_workspace_id" {
  description = "The Log Analytics workspace ID"
  type        = string
}

# Database variables
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
}

variable "administrator_password" {
  description = "The administrator password for the database server"
  type        = string
}

variable "sku_name" {
  description = "The SKU name for the database server"
  type        = string
}

variable "postgres_version" {
  description = "The PostgreSQL version"
  type        = string
}

variable "storage_mb" {
  description = "The storage size in MB"
  type        = number
}

variable "backup_retention_days" {
  description = "The backup retention period in days"
  type        = number
}

variable "public_network_access_enabled" {
  description = "Whether public network access is enabled"
  type        = bool
}

# Storage variables
variable "container_name" {
  description = "The name of the storage container"
  type        = string
}

variable "container_access_type" {
  description = "The access type for the storage container"
  type        = string
}


# Cert Manager variables
variable "cert_manager_namespace" {
  description = "The namespace for cert-manager"
  type        = string
}

variable "cert_manager_install_timeout" {
  description = "Timeout for installing cert-manager"
  type        = number
}

variable "cert_manager_chart_version" {
  description = "Version of the cert-manager helm chart"
  type        = string
}

# Operator variables
variable "operator_namespace" {
  description = "The namespace for the Materialize operator"
  type        = string
}

# Materialize Instance variables
variable "install_materialize_instance" {
  description = "Whether to install the Materialize instance"
  type        = bool
}

variable "instance_name" {
  description = "The name of the Materialize instance"
  type        = string
}

variable "instance_namespace" {
  description = "The namespace of the Materialize instance"
  type        = string
}

variable "license_key" {
  description = "Materialize license key"
  type        = string
  default     = null
  sensitive   = true
}

variable "external_login_password_mz_system" {
  description = "The password for the external login to the Materialize instance"
  type        = string
  sensitive   = true
}
