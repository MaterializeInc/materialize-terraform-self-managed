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

variable "vnet_address_space" {
  description = "Address space for the VNet"
  type        = string
  nullable    = false
}

variable "aks_subnet_cidr" {
  description = "CIDR range for the AKS subnet"
  type        = string
  nullable    = false
}

variable "postgres_subnet_cidr" {
  description = "CIDR range for the PostgreSQL subnet"
  type        = string
  nullable    = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "nat_gateway_idle_timeout" {
  description = "The idle timeout in minutes for the NAT Gateway"
  type        = number
  default     = 4
  nullable    = false
}
