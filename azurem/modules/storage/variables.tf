variable "resource_group_name" {
  description = "The name of the resource group"
  type        = string
}

variable "location" {
  description = "The location where resources will be created"
  type        = string
}

variable "prefix" {
  description = "Prefix to be used for resource names"
  type        = string
}

variable "identity_principal_id" {
  description = "The principal ID of the workload identity"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "subnets" {
  description = "the subnet of the vnet that should be able to access this storage account"
  type        = list(string)
  default     = []
}

variable "account_tier" {
  description = "Defines the Tier to use for this storage account. Valid options are Standard and Premium"
  type        = string
  default     = "Premium"
}

variable "account_replication_type" {
  description = "Defines the type of replication to use for this storage account. Valid options are LRS, GRS, RAGRS, ZRS, GZRS and RAGZRS"
  type        = string
  default     = "LRS"
}

variable "account_kind" {
  description = "Defines the Kind of account. Valid options are BlobStorage, BlockBlobStorage, FileStorage, Storage and StorageV2"
  type        = string
  default     = "BlockBlobStorage"
}

variable "container_name" {
  description = "The name of the Container which should be created within the Storage Account"
  type        = string
}

variable "container_access_type" {
  description = "The Access Level configured for this Container. Possible values are blob, container or private"
  type        = string
  default     = "private"
}
