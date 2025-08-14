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

variable "vnet_address_space" {
  description = "The address space of the virtual network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "The CIDR of the subnet"
  type        = string
  default     = "10.0.0.0/24"
}

variable "postgres_subnet_cidr" {
  description = "The CIDR of the postgres subnet"
  type        = string
  default     = "10.0.1.0/24"
}
