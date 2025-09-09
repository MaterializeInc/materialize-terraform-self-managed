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

variable "identity_principal_id" {
  description = "The principal ID of the workload identity"
  type        = string
  nullable    = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "subnets" {
  description = "The subnet of the vnet that should be able to access this storage account"
  type        = list(string)
  default     = []
  nullable    = false
}

variable "account_tier" {
  description = "Defines the Tier to use for this storage account. Valid options are Standard and Premium."
  type        = string
  default     = "Premium"

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "Valid values for account_tier are: Standard, Premium."
  }
}

variable "account_replication_type" {
  description = "Defines the type of replication to use for this storage account. Valid options are LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.account_replication_type)
    error_message = "Valid values for account_replication_type are: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# For BlockBlobStorage and FileStorage accounts only Premium is valid. Changing this forces a new resource to be created.
# TODO: should we add cross field validation to ensure that account_tier is Premium if account_kind is BlockBlobStorage or FileStorage?
variable "account_kind" {
  description = "Defines the Kind of account. Valid options are BlobStorage, BlockBlobStorage, FileStorage, Storage, StorageV2."
  type        = string
  default     = "BlockBlobStorage"

  validation {
    condition     = contains(["BlobStorage", "BlockBlobStorage", "FileStorage", "Storage", "StorageV2"], var.account_kind)
    error_message = "Valid values for account_kind are: BlobStorage, BlockBlobStorage, FileStorage, Storage, StorageV2."
  }
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
