variable "project_id" {
  description = "The ID of the project where resources will be created"
  type        = string
}

variable "region" {
  description = "The region where resources will be created"
  type        = string
}

variable "prefix" {
  description = "Prefix to be used for resource names"
  type        = string
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
}

variable "mtu" {
  description = "MTU for the network"
  type        = number
  default     = 1460 # Optimized for GKE
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
}

variable "log_config_filter" {
  description = "Filter for logging"
  type        = string
  default     = "ERRORS_ONLY"
}

variable "source_subnetwork_ip_ranges_to_nat" {
  description = "Source subnetwork IP ranges to NAT"
  type        = string
  default     = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

variable "create_router" {
  description = "Whether to create a router"
  type        = bool
  default     = true
}

variable "router_asn" {
  description = "Router ASN"
  type        = string
  default     = "64514"
}
