variable "project_id" {
  description = "The ID of the project where resources will be created"
  type        = string
  nullable    = false
}

variable "region" {
  description = "The region where resources will be created"
  type        = string
  nullable    = false
}

variable "prefix" {
  description = "Prefix to be used for resource names"
  type        = string
  nullable    = false
}

variable "subnets" {
  description = "List of subnet configurations including primary CIDR and secondary ranges"
  type = list(object({
    name           = string
    cidr           = string
    region         = string
    private_access = optional(bool, true)
    secondary_ranges = optional(list(object({
      range_name    = string
      ip_cidr_range = string
    })), [])
  }))
  nullable = false
}

variable "mtu" {
  description = "MTU for the network"
  type        = number
  default     = 1460 # Optimized for GKE
  nullable    = false
}

variable "routes" {
  description = "Additional routes for the network (beyond the default route managed internally)"
  type        = list(any)
  default     = []
}

variable "log_config_enable" {
  description = "Enable logging for the network"
  type        = bool
  default     = true
  nullable    = false
}

variable "log_config_filter" {
  description = "Filter for logging"
  type        = string
  default     = "ERRORS_ONLY"

  validation {
    condition     = contains(["ERRORS_ONLY", "TRANSLATIONS_ONLY", "ALL"], var.log_config_filter)
    error_message = "Log config filter must be one of ERRORS_ONLY, TRANSLATIONS_ONLY, or ALL"
  }
}

variable "source_subnetwork_ip_ranges_to_nat" {
  description = "Source subnetwork IP ranges to NAT"
  type        = string
  default     = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  validation {
    condition     = contains(["ALL_SUBNETWORKS_ALL_IP_RANGES", "ALL_SUBNETWORKS_ALL_PRIMARY_IP_RANGES", "LIST_OF_SUBNETWORKS"], var.source_subnetwork_ip_ranges_to_nat)
    error_message = "Source subnetwork IP ranges to NAT must be one of ALL_SUBNETWORKS_ALL_IP_RANGES, ALL_SUBNETWORKS_ALL_PRIMARY_IP_RANGES, or LIST_OF_SUBNETWORKS"
  }
}

variable "create_router" {
  description = "Whether to create a router"
  type        = bool
  default     = true
  nullable    = false
}

variable "router_asn" {
  description = "Router ASN"
  type        = string
  default     = "64514"
  nullable    = false
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default     = {}
}
