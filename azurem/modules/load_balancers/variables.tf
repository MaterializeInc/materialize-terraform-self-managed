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
