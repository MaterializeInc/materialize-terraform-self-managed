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
  nullable    = false
}

variable "prefix" {
  description = "The prefix for the resource group."
  type        = string
  nullable    = false
}

variable "tags" {
  description = "The tags for the resource group."
  type        = map(string)
  nullable    = false
}

variable "aks_subnet_id" {
  description = "The ID of the AKS subnet."
  type        = string
  nullable    = false
}

variable "ingress_cidr_blocks" {
  description = "CIDR blocks that are allowed to reach the Azure LoadBalancers."
  type        = list(string)
  default     = [""]
  nullable    = false
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

# variable "ingress_cidr_blocks" {
#   description = "CIDR blocks that are allowed to reach the Azure LoadBalancers."
#   type        = list(string)
#   nullable    = false
# }
