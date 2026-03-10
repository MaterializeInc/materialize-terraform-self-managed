variable "project_id" {
  description = "The GCP project ID."
  type        = string
  nullable    = false
}

variable "dns_zone_name" {
  description = "The name of the Cloud DNS managed zone."
  type        = string
  nullable    = false
}

variable "balancerd_hostname" {
  description = "The hostname for balancerd (without trailing dot)."
  type        = string
  nullable    = false
}

variable "console_hostname" {
  description = "The hostname for the console (without trailing dot)."
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

variable "dns_ttl" {
  description = "TTL for DNS records in seconds."
  type        = number
  default     = 300
  nullable    = false
}
