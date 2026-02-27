# =============================================================================
# Migration Reference Variables
# =============================================================================
#
# Update these variables to match your existing infrastructure.
#
# =============================================================================

variable "aws_region" {
  description = "The AWS region where your resources exist"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "The AWS profile to use for authentication"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources (should match existing tags)"
  type        = map(string)
  default     = {}
}

variable "name_prefix" {
  description = "Prefix used for all resource names (must match existing)"
  type        = string
}

variable "license_key" {
  description = "Materialize license key"
  type        = string
  sensitive   = true
}

variable "force_rollout" {
  description = "UUID to force a rollout"
  type        = string
  default     = "00000000-0000-0000-0000-000000000003"
}

variable "request_rollout" {
  description = "UUID to request a rollout"
  type        = string
  default     = "00000000-0000-0000-0000-000000000003"
}

variable "ingress_cidr_blocks" {
  description = "List of CIDR blocks to allow access to Materialize load balancers"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  nullable    = true

  validation {
    condition     = var.ingress_cidr_blocks == null || alltrue([for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All CIDR blocks must be valid IPv4 CIDR notation."
  }
}

variable "k8s_apiserver_authorized_networks" {
  description = "List of CIDR blocks allowed to access the EKS API server"
  type        = list(string)
  nullable    = false
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for cidr in var.k8s_apiserver_authorized_networks : can(cidrhost(cidr, 0))])
    error_message = "All CIDR blocks must be valid IPv4 CIDR notation."
  }
}

variable "internal_load_balancer" {
  description = "Whether to use an internal load balancer"
  type        = bool
  default     = true
}

variable "old_db_password" {
  description = "Existing database password (used for migration)"
  type        = string
  sensitive   = true
}

variable "external_login_password_mz_system" {
  description = "Password for mz_system user (used for migration)"
  type        = string
  sensitive   = true
}

variable "environment" {
  description = "Environment name from the old module (e.g., 'dev', 'staging', 'prod'). Used to construct the S3 persist path to match existing data."
  type        = string
}

variable "use_self_signed_cluster_issuer" {
  description = "Whether to enable TLS using the self-signed cluster issuer. Must match your old module's setting to preserve TLS configuration."
  type        = bool
  default     = true
}
