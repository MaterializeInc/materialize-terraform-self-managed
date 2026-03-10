variable "prefix" {
  description = "Prefix for resource names."
  type        = string
  nullable    = false
}

variable "resource_group_name" {
  description = "The name of the resource group."
  type        = string
  nullable    = false
}

variable "location" {
  description = "The Azure region."
  type        = string
  nullable    = false
}

variable "tags" {
  description = "Tags to apply to resources."
  type        = map(string)
  default     = {}
  nullable    = false
}
