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

variable "aks_config" {
  description = "AKS cluster configuration"
  type = object({
    kubernetes_version         = string
    service_cidr               = string
    enable_azure_monitor       = bool
    log_analytics_workspace_id = optional(string)
  })
  default = {
    kubernetes_version         = "1.32"
    service_cidr               = "10.1.0.0/16"
    enable_azure_monitor       = false
    log_analytics_workspace_id = null
  }
}

variable "node_pool_config" {
  description = "Materialize node pool configuration"
  type = object({
    vm_size              = string
    auto_scaling_enabled = bool
    min_nodes            = number
    max_nodes            = number
    node_count           = number
    disk_size_gb         = number
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

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Environment = "development"
    Project     = "materialize"
  }
}


variable "install_cert_manager" {
  description = "Whether to install cert-manager."
  type        = bool
  default     = true
}

variable "cert_manager_namespace" {
  description = "The name of the namespace in which cert-manager is or will be installed."
  type        = string
  default     = "cert-manager"
}

variable "cert_manager_install_timeout" {
  description = "Timeout for installing the cert-manager helm chart, in seconds."
  type        = number
  default     = 300
}

variable "cert_manager_chart_version" {
  description = "Version of the cert-manager helm chart to install."
  type        = string
  default     = "v1.17.1"
}

# Disk support configuration
variable "enable_disk_support" {
  description = "Enable disk support for Materialize using OpenEBS and local SSDs. When enabled, this configures OpenEBS, runs the disk setup script, and creates appropriate storage classes."
  type        = bool
  default     = true
}

variable "disk_support_config" {
  description = "Advanced configuration for disk support (only used when enable_disk_support = true)"
  type = object({
    install_openebs   = optional(bool, true)
    openebs_version   = optional(string, "4.2.0")
    openebs_namespace = optional(string, "openebs")
  })
  default = {}
}

variable "disk_setup_image" {
  description = "Docker image for the disk setup script"
  type        = string
  default     = "materialize/ephemeral-storage-setup-image:v0.1.1"
}


# Materialize Helm Chart Variables
variable "install_materialize_operator" {
  description = "Whether to install the Materialize operator"
  type        = bool
  default     = true
}

variable "install_materialize_instance" {
  description = "Whether to install the Materialize instance. Default is false as it requires the Kubernetes cluster to be created first."
  type        = bool
  default     = false
}
