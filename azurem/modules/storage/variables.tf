variable "resource_group_name" {
  description = "The name of the resource group"
  type        = string
  nullable    = false
}

variable "location" {
  description = "The location where resources will be created"
  type        = string
  nullable    = false
}

variable "prefix" {
  description = "Prefix to be used for resource names"
  type        = string
  nullable    = false
}

variable "workload_identity_principal_id" {
  description = "The principal ID of the workload identity"
  type        = string
  nullable    = false
}

variable "storage_account_tags" {
  description = "Tags to apply to storage account"
  type        = map(string)
  default     = {}
}

variable "subnets" {
  description = "The subnet of the vnet that should be able to access this storage account"
  type        = list(string)
  default     = []
  nullable    = false
}

variable "container_name" {
  description = "The name of the Container which should be created within the Storage Account"
  type        = string
  nullable    = false
}

variable "container_access_type" {
  description = "The Access Level configured for this Container. Valid values are: private, blob, container."
  type        = string
  default     = "private"

  validation {
    condition     = contains(["private", "blob", "container"], var.container_access_type)
    error_message = "Valid values for container_access_type are: private, blob, container."
  }
}

variable "workload_identity_id" {
  description = "The ID of the workload identity for federated credential"
  type        = string
  nullable    = false
}

variable "oidc_issuer_url" {
  description = "The OIDC issuer URL of the AKS cluster"
  type        = string
  nullable    = false
}

variable "service_account_namespace" {
  description = "Kubernetes namespace for the service account that will use workload identity"
  type        = string
  nullable    = false
}

variable "service_account_name" {
  description = "Kubernetes service account name that will use workload identity"
  type        = string
  nullable    = false
}
