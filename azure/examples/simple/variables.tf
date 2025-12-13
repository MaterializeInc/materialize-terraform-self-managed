variable "subscription_id" {
  description = "The ID of the Azure subscription"
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group which will be created."
  type        = string
}

variable "location" {
  description = "The location of the Azure subscription"
  type        = string
  default     = "westus2"
}

variable "name_prefix" {
  description = "The prefix of the Azure subscription"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources created."
  type        = map(string)
}

variable "ingress_cidr_blocks" {
  description = "CIDR blocks that can reach the Azure LoadBalancer frontends."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition = alltrue([
      for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All ingress_cidr_blocks must be valid CIDR notation (e.g., '10.0.0.0/8' or '0.0.0.0/0')."
  }
}

variable "license_key" {
  description = "Materialize license key"
  type        = string
  default     = null
  sensitive   = true
}

variable "api_server_authorized_ip_ranges" {
  description = "List of authorized IP ranges that can access the Kubernetes API server when public access is available. Defaults to ['0.0.0.0/0'] (allow all). For production, restrict to specific IPs (e.g., ['203.0.113.0/24'])"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Explicit default: allow all IPs
  nullable    = true

  validation {
    condition = (
      var.api_server_authorized_ip_ranges == null ||
      alltrue([
        for cidr in var.api_server_authorized_ip_ranges :
        can(cidrhost(cidr, 0))
      ])
    )
    error_message = "All api_server_authorized_ip_ranges must be valid CIDR blocks (e.g., '203.0.113.0/24')."
  }
}
