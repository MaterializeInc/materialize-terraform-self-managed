variable "project_id" {
  description = "The ID of the project where resources will be created"
  type        = string
}

variable "region" {
  description = "The region where resources will be created"
  type        = string
  default     = "us-central1"
}

variable "labels" {
  description = "Labels to apply to resources created."
  type        = map(string)
}

variable "name_prefix" {
  description = "Prefix to be used for resource names"
  type        = string
  default     = "materialize"
}

variable "license_key" {
  description = "Materialize license key"
  type        = string
  default     = null
  sensitive   = true
}

variable "ingress_cidr_blocks" {
  description = "The CIDR blocks that are allowed to reach the Load Balancer."
  type        = list(string)
  default     = ["0.0.0.0/0"]
  nullable    = true

  validation {
    condition = var.ingress_cidr_blocks == null || alltrue([
      for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All ingress_cidr_blocks must be valid CIDR notation (e.g., '10.0.0.0/8' or '0.0.0.0/0')."
  }
}

variable "k8s_apiserver_authorized_networks" {
  description = "The CIDR blocks that are allowed to reach the Kubernetes master endpoint."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [{
    cidr_block   = "0.0.0.0/0"
    display_name = "Default Placeholder for authorized networks"
  }]
  nullable = false

  validation {
    condition = alltrue([
      for network in var.k8s_apiserver_authorized_networks : can(cidrhost(network.cidr_block, 0))
    ])
    error_message = "All k8s_apiserver_authorized_networks must be valid CIDR notation (e.g., '10.0.0.0/8' or '0.0.0.0/0')."
  }
}

variable "internal_load_balancer" {
  description = "Whether to use an internal load balancer"
  type        = bool
  default     = true
}

variable "enable_public_tls" {
  description = "Enable public TLS with ACME certificates and Cloud DNS"
  type        = bool
  default     = false
}

variable "dns_zone_name" {
  description = "Name of the Cloud DNS managed zone (required when enable_public_tls is true)"
  type        = string
  default     = null
}

variable "balancerd_hostname" {
  description = "Hostname for the balancerd service (required when enable_public_tls is true)"
  type        = string
  default     = null
}

variable "console_hostname" {
  description = "Hostname for the console service (required when enable_public_tls is true)"
  type        = string
  default     = null
}

variable "acme_email" {
  description = "Email address for ACME certificate registration (required when enable_public_tls is true)"
  type        = string
  default     = null
}

variable "acme_server" {
  description = "ACME server URL for certificate issuance"
  type        = string
  default     = "https://dv.acme-v02.api.pki.goog/directory"
}
