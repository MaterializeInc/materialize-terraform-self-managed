variable "instance_name" {
  description = "The name of the Materialize instance."
  type        = string
}

variable "namespace" {
  description = "The kubernetes namespace to create the LoadBalancer Service in."
  type        = string
}

variable "resource_id" {
  description = "The resource_id in the Materialize status."
  type        = string
}

variable "internal" {
  description = "Whether the load balancer is internal to the VPC."
  type        = bool
  default     = true
}

variable "materialize_console_port_config" {
  description = "Port configuration for Materialize console service"
  type = object({
    name        = string
    port        = number
    target_port = number
    protocol    = string
  })
  default = {
    name        = "http"
    port        = 8080
    target_port = 8080
    protocol    = "TCP"
  }
}

variable "materialize_balancerd_sql_port_config" {
  description = "SQL port configuration for Materialize balancerd service"
  type = object({
    name        = string
    port        = number
    target_port = number
    protocol    = string
  })
  default = {
    name        = "sql"
    port        = 6875
    target_port = 6875
    protocol    = "TCP"
  }
}

variable "materialize_balancerd_https_port_config" {
  description = "HTTPS port configuration for Materialize balancerd service"
  type = object({
    name        = string
    port        = number
    target_port = number
    protocol    = string
  })
  default = {
    name        = "https"
    port        = 6876
    target_port = 6876
    protocol    = "TCP"
  }
}
