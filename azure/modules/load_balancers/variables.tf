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

variable "resource_group_name" {
  description = "The name of the resource group."
  type        = string
  nullable    = false
}

variable "location" {
  description = "The location of the resource group."
  type        = string
  nullable    = true

  validation {
    condition     = var.internal || var.location != null
    error_message = "location must be provided when creating a public load balancer (internal = false)."
  }
}

variable "prefix" {
  description = "The prefix for the resource group."
  type        = string
  nullable    = true

  validation {
    condition     = var.internal || var.prefix != null
    error_message = "prefix must be provided when creating a public load balancer (internal = false)."
  }
}

variable "tags" {
  description = "The tags for the resource group."
  type        = map(string)
  nullable    = true

  validation {
    condition     = var.internal || var.tags != null
    error_message = "tags must be provided when creating a public load balancer (internal = false)."
  }
}

variable "aks_subnet_id" {
  description = "The ID of the AKS subnet."
  type        = string
  nullable    = true

  validation {
    condition     = var.internal || var.aks_subnet_id != null
    error_message = "aks_subnet_id must be provided when creating a public load balancer (internal = false)."
  }
}

variable "ingress_cidr_blocks" {
  description = "CIDR blocks that are allowed to reach the Azure LoadBalancers."
  type        = list(string)
  default     = ["0.0.0.0/0"]
  nullable    = true

  validation {
    condition = var.internal ? true : (
      var.ingress_cidr_blocks != null && alltrue([
        for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))
      ])
    )
    error_message = "ingress_cidr_blocks must be provided and contain valid CIDR notation when creating a public load balancer (internal = false)."
  }
}

variable "resource_id" {
  description = "The resource_id in the Materialize status."
  type        = string
  nullable    = false
}

variable "internal" {
  description = "Whether the load balancer is internal to the VNet. Defaults to false (public) to allow external access to Materialize. Set to true for VNet-only access."
  type        = bool
  default     = false
  nullable    = false
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
