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

variable "enable_disk_setup" {
  description = "Enable disk setup for Materialize nodes"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Environment = "development"
    Project     = "materialize"
  }
}
