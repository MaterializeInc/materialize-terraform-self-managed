variable "subscription_id" {
  description = "The ID of the Azure subscription"
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group"
  type        = string
  default     = "materialize"
}

variable "location" {
  description = "The location of the Azure subscription"
  type        = string
  default     = "westus2"
}

variable "prefix" {
  description = "The prefix of the Azure subscription"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Environment = "development"
    Project     = "materialize"
  }
}

# Feature Flags
variable "enable_disk_support" {
  description = "Enable disk support for Materialize using OpenEBS and local SSDs. When enabled, this configures OpenEBS, runs the disk setup script, and creates appropriate storage classes."
  type        = bool
  default     = true
}

variable "install_materialize_instance" {
  description = "Whether to install the Materialize instance. Default is false as it requires the Kubernetes cluster to be created first."
  type        = bool
  default     = false
}

# Networking Module Configuration
variable "vnet_config" {
  description = "Virtual network configuration"
  type = object({
    address_space        = string
    aks_subnet_cidr      = string
    postgres_subnet_cidr = string
  })
  default = {
    address_space        = "10.0.0.0/16"
    aks_subnet_cidr      = "10.0.0.0/20"
    postgres_subnet_cidr = "10.0.1.0/24"
  }
}

# AKS Module Configuration
variable "aks_config" {
  description = "AKS cluster configuration"
  type = object({
    kubernetes_version         = string
    service_cidr               = string
    enable_azure_monitor       = optional(bool, false)
    log_analytics_workspace_id = optional(string, null)
    # System-only node pool configuration
    default_node_pool_vm_size     = optional(string, "Standard_D2s_v3")
    default_node_pool_node_count  = optional(number, 2)
    default_node_pool_system_only = optional(bool, true)
  })
  default = {
    kubernetes_version            = "1.32"
    service_cidr                  = "10.1.0.0/16"
    enable_azure_monitor          = false
    log_analytics_workspace_id    = null
    default_node_pool_vm_size     = "Standard_D2s_v3"
    default_node_pool_node_count  = 2
    default_node_pool_system_only = true
  }
}

# Node Pool Module Configuration
variable "node_pool_config" {
  description = "Materialize node pool configuration"
  type = object({
    vm_size              = optional(string, "Standard_E4pds_v6")
    auto_scaling_enabled = optional(bool, true)
    min_nodes            = optional(number, 1)
    max_nodes            = optional(number, 5)
    node_count           = optional(number, null)
    disk_size_gb         = optional(number, 100)
  })
  default = {
    vm_size              = "Standard_E4pds_v6"
    auto_scaling_enabled = true
    min_nodes            = 1
    max_nodes            = 5
    node_count           = null
    disk_size_gb         = 100
  }
}

# Database Module Configuration
variable "database_config" {
  description = "Database configuration"
  type = object({
    sku_name                      = optional(string, "GP_Standard_D2s_v3")
    postgres_version              = optional(string, "15")
    storage_mb                    = optional(number, 32768)
    backup_retention_days         = optional(number, 7)
    administrator_login           = optional(string, "materialize")
    administrator_password        = optional(string, null)
    database_name                 = optional(string, "materialize")
    public_network_access_enabled = optional(bool, false)
  })
  default = {
    sku_name                      = "GP_Standard_D2s_v3"
    postgres_version              = "15"
    storage_mb                    = 32768
    backup_retention_days         = 7
    administrator_login           = "materialize"
    administrator_password        = null # Will generate random password
    database_name                 = "materialize"
    public_network_access_enabled = false
  }
}

# Storage Module Configuration
variable "storage_config" {
  description = "Storage configuration"
  type = object({
    account_tier             = optional(string, "Premium")
    account_replication_type = optional(string, "LRS")
    account_kind             = optional(string, "BlockBlobStorage")
    container_name           = optional(string, "materialize")
    container_access_type    = optional(string, "private")
  })
  default = {
    # https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blob-block-blob-premium#premium-scenarios
    account_tier             = "Premium"
    account_replication_type = "LRS"
    account_kind             = "BlockBlobStorage"
    container_name           = "materialize"
    container_access_type    = "private"
  }
}

# Certificate Manager Module Configuration
variable "cert_manager_config" {
  description = "Certificate manager configuration"
  type = object({
    install_cert_manager         = optional(bool, true)
    cert_manager_namespace       = optional(string, "cert-manager")
    cert_manager_install_timeout = optional(number, 300)
    cert_manager_chart_version   = optional(string, "v1.18.0")
  })
  default = {
    install_cert_manager         = true
    cert_manager_namespace       = "cert-manager"
    cert_manager_install_timeout = 300
    cert_manager_chart_version   = "v1.18.0"
  }
}

# OpenEBS Module Configuration
variable "disk_support_config" {
  description = "Advanced configuration for disk support (only used when enable_disk_support = true)"
  type = object({
    install_openebs          = optional(bool, true)
    openebs_version          = optional(string, "4.2.0")
    create_openebs_namespace = optional(bool, true)
    openebs_namespace        = optional(string, "openebs")
  })
  default = {
    install_openebs          = true
    openebs_version          = "4.2.0"
    create_openebs_namespace = true
    openebs_namespace        = "openebs"
  }
}

variable "disk_setup_image" {
  description = "Docker image for the disk setup script"
  type        = string
  default     = "materialize/ephemeral-storage-setup-image:v0.1.1"
}

# Materialize Instance Module Configuration
variable "materialize_instance_config" {
  description = "Configuration for the Materialize instance"
  type = object({
    instance_name      = optional(string, "main")
    instance_namespace = optional(string, "materialize-environment")
  })
  default = {
    instance_name      = "main"
    instance_namespace = "materialize-environment"
  }
}

# Load Balancer Module Configuration
variable "load_balancer_config" {
  description = "Configuration for the load balancer"
  type = object({
    internal = optional(bool, true)
  })
  default = {
    internal = true
  }
}
