variable "resource_group_name" {
  description = "The resource group containing the DNS zone."
  type        = string
  nullable    = false
}

variable "dns_zone_name" {
  description = "The name of the Azure DNS zone."
  type        = string
  nullable    = false
}

variable "balancerd_domain_name" {
  description = "The record name for balancerd (relative to the zone)."
  type        = string
  nullable    = false
}

variable "console_domain_name" {
  description = "The record name for the console (relative to the zone)."
  type        = string
  nullable    = false
}

variable "balancerd_ip" {
  description = "The IP address for the balancerd A record."
  type        = string
  nullable    = false
}

variable "console_ip" {
  description = "The IP address for the console A record."
  type        = string
  nullable    = false
}

variable "ttl" {
  description = "TTL for DNS records in seconds."
  type        = number
  default     = 300
  nullable    = false
}

variable "tags" {
  description = "Tags to apply to resources."
  type        = map(string)
  default     = {}
  nullable    = false
}
