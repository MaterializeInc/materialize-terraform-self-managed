variable "project_id" {
  description = "The ID of the project in which to create the firewall rule."
  type        = string
  nullable    = false
}

variable "network_name" {
  description = "The name of the network in which to create the firewall rule."
  type        = string
  nullable    = false
}

variable "prefix" {
  description = "Prefix to be used for resource names"
  type        = string
  nullable    = false
}

variable "node_service_account_email" {
  description = "The email of the node service account."
  type        = string
  nullable    = false
}

variable "instance_name" {
  description = "The name of the Materialize instance."
  type        = string
  nullable    = false
}

variable "namespace" {
  description = "The kubernetes namespace to create the LoadBalancer Service in."
  type        = string
  nullable    = false
}

variable "resource_id" {
  description = "The resource_id in the Materialize status."
  type        = string
  nullable    = false
}

variable "internal" {
  description = "Whether the load balancer is internal to the VPC."
  type        = bool
  default     = true
  nullable    = false
}

variable "ingress_cidr_blocks" {
  description = "List of external IP CIDR blocks to allow ingress to External Load Balancer. Required when internal = false, must be null when internal = true."
  type        = list(string)
  nullable    = true
  default     = null

  validation {
    condition = var.internal ? true : (
      var.ingress_cidr_blocks != null && length(var.ingress_cidr_blocks) > 0 && alltrue([
        for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))
      ])
    )
    error_message = "ingress_cidr_blocks must be provided (non-null, non-empty) when internal = false, and must be null when internal = true. All CIDR blocks must be valid CIDR notation."
  }
}

variable "materialize_console_port" {
  description = "Port configuration for Materialize console service"
  type        = number
  default     = 8080
  nullable    = false
}

variable "materialize_balancerd_sql_port" {
  description = "SQL port configuration for Materialize balancerd service"
  type        = number
  default     = 6875
  nullable    = false
}

variable "materialize_balancerd_https_port" {
  description = "HTTPS port configuration for Materialize balancerd service"
  type        = number
  default     = 6876
  nullable    = false
}
