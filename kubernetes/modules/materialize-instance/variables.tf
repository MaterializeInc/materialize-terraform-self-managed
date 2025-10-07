variable "instance_name" {
  description = "Name of the Materialize instance"
  type        = string
  nullable    = false
}

variable "create_namespace" {
  description = "Whether to create the Kubernetes namespace. Set to false if the namespace already exists."
  type        = bool
  default     = true
  nullable    = false
}

variable "instance_namespace" {
  description = "Kubernetes namespace for the instance."
  type        = string
  nullable    = false
}

variable "metadata_backend_url" {
  description = "PostgreSQL connection URL for metadata backend"
  type        = string
  sensitive   = true
  nullable    = false
}

variable "persist_backend_url" {
  description = "S3 connection URL for persist backend"
  type        = string
  nullable    = false
}

variable "license_key" {
  description = "Materialize license key"
  type        = string
  default     = null
  sensitive   = true
}

# Environmentd Configuration
variable "environmentd_version" {
  description = "Version of environmentd to use"
  type        = string
  default     = "v0.155.0" # META: mz version
  nullable    = false
}

variable "environmentd_extra_env" {
  description = "Extra environment variables for environmentd"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "environmentd_extra_args" {
  description = "Extra command line arguments for environmentd"
  type        = list(string)
  default     = []
}

# Resource Requirements
variable "cpu_request" {
  description = "CPU request for environmentd"
  type        = string
  default     = "1"
  nullable    = false
}

variable "memory_request" {
  description = "Memory request for environmentd"
  type        = string
  default     = "1Gi"
  nullable    = false
}

variable "memory_limit" {
  description = "Memory limit for environmentd"
  type        = string
  default     = "1Gi"
  nullable    = false
}

# Rollout Configuration
variable "in_place_rollout" {
  description = "Whether to perform in-place rollouts"
  type        = bool
  default     = true
  nullable    = false
}

variable "request_rollout" {
  description = "UUID to request a rollout"
  type        = string
  default     = "00000000-0000-0000-0000-000000000001"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.request_rollout))
    error_message = "Request rollout must be a valid UUID in the format xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  }
}

variable "force_rollout" {
  description = "UUID to force a rollout"
  type        = string
  default     = "00000000-0000-0000-0000-000000000001"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.force_rollout))
    error_message = "Force rollout must be a valid UUID in the format xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  }
}

# Balancer Resource Requirements
variable "balancer_memory_request" {
  description = "Memory request for balancer"
  type        = string
  default     = "256Mi"
  nullable    = false
}

variable "balancer_memory_limit" {
  description = "Memory limit for balancer"
  type        = string
  default     = "256Mi"
  nullable    = false
}

variable "balancer_cpu_request" {
  description = "CPU request for balancer"
  type        = string
  default     = "100m"
  nullable    = false
}

variable "authenticator_kind" {
  description = "Kind of authenticator to use for Materialize instance"
  type        = string
  default     = "None"
  nullable    = false
  validation {
    condition     = contains(["None", "Password"], var.authenticator_kind)
    error_message = "Authenticator kind must be either 'None' or 'Password'"
  }
}

variable "external_login_password_mz_system" {
  description = "Password for external login to mz_system. Must be set if authenticator_kind is 'Password'."
  type        = string
  default     = null
  sensitive   = true
}

variable "service_account_annotations" {
  description = "Annotations for the service account associated with the materialize instance. Useful for IAM roles assigned to the service account."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "pod_labels" {
  description = "Labels for the materialize instance pod"
  type        = map(string)
  default     = {}
  nullable    = false
}


variable "issuer_ref" {
  description = "Reference to a cert-manager Issuer or ClusterIssuer."
  type = object({
    name = string
    kind = string
  })
  default = null
}
