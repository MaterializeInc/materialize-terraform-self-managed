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
  default     = "v26.7.0" # META: mz version
  nullable    = false
}

variable "environmentd_extra_env" {
  description = "DEPRECATED: Use materialize_spec_override.environmentdExtraEnv instead. Extra environment variables for environmentd."
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "environmentd_extra_args" {
  description = "DEPRECATED: Use materialize_spec_override.environmentdExtraArgs instead. Extra command line arguments for environmentd."
  type        = list(string)
  default     = []
}

# Resource Requirements
variable "cpu_request" {
  description = "DEPRECATED: Use materialize_spec_override.environmentdResourceRequirements instead. CPU request for environmentd."
  type        = string
  default     = "1"
  nullable    = false
}

variable "memory_request" {
  description = "DEPRECATED: Use materialize_spec_override.environmentdResourceRequirements instead. Memory request for environmentd."
  type        = string
  default     = "4095Mi"
  nullable    = false
}

variable "memory_limit" {
  description = "DEPRECATED: Use materialize_spec_override.environmentdResourceRequirements instead. Memory limit for environmentd."
  type        = string
  default     = "4Gi"
  nullable    = false
}

# Rollout Configuration
variable "rollout_strategy" {
  description = "DEPRECATED: Use materialize_spec_override.rolloutStrategy instead. Strategy to use for rollouts."
  type        = string
  default     = "WaitUntilReady"
  nullable    = false
  validation {
    condition     = contains(["WaitUntilReady", "ImmediatelyPromoteCausingDowntime"], var.rollout_strategy)
    error_message = "Rollout strategy must be either 'WaitUntilReady' or 'ImmediatelyPromoteCausingDowntime'"
  }
}

variable "request_rollout" {
  description = "DEPRECATED: Use materialize_spec_override.requestRollout instead. UUID to request a rollout."
  type        = string
  default     = "00000000-0000-0000-0000-000000000001"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.request_rollout))
    error_message = "Request rollout must be a valid UUID in the format xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  }
}

variable "force_rollout" {
  description = "DEPRECATED: Use materialize_spec_override.forceRollout instead. UUID to force a rollout."
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
  description = "DEPRECATED: Use materialize_spec_override.balancerdResourceRequirements instead. Memory request for balancer."
  type        = string
  default     = "256Mi"
  nullable    = false
}

variable "balancer_memory_limit" {
  description = "DEPRECATED: Use materialize_spec_override.balancerdResourceRequirements instead. Memory limit for balancer."
  type        = string
  default     = "256Mi"
  nullable    = false
}

variable "balancer_cpu_request" {
  description = "DEPRECATED: Use materialize_spec_override.balancerdResourceRequirements instead. CPU request for balancer."
  type        = string
  default     = "100m"
  nullable    = false
}

variable "authenticator_kind" {
  description = "DEPRECATED: Use materialize_spec_override.authenticatorKind instead. Kind of authenticator to use for Materialize instance. Password or Sasl (SCRAM) is recommended for production."
  type        = string
  default     = "Password"
  nullable    = false
  validation {
    condition     = contains(["None", "Password", "Sasl"], var.authenticator_kind)
    error_message = "Authenticator kind must be one of: 'None', 'Password', or 'Sasl'"
  }
}

variable "external_login_password_mz_system" {
  description = "Password for external login to mz_system. Must be set if authenticator_kind is 'Password' or 'Sasl'."
  type        = string
  default     = null
  sensitive   = true
}

variable "service_account_annotations" {
  description = "DEPRECATED: Use materialize_spec_override.serviceAccountAnnotations instead. Annotations for the service account associated with the materialize instance. Useful for IAM roles assigned to the service account."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "pod_labels" {
  description = "DEPRECATED: Use materialize_spec_override.podLabels instead. Labels for the materialize instance pod."
  type        = map(string)
  default     = {}
  nullable    = false
}


variable "issuer_ref" {
  description = "DEPRECATED: Use materialize_spec_override.internalCertificateSpec.issuerRef instead. Reference to a cert-manager Issuer or ClusterIssuer."
  type = object({
    name = string
    kind = string
  })
  default = null
}

