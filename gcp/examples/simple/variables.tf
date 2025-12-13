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

variable "force_rollout" {
  description = "DEPRECATED: Use materialize_spec_override.forceRollout instead. UUID to force a rollout of the environment."
  type        = string
  default     = null
}

variable "request_rollout" {
  description = "DEPRECATED: Use materialize_spec_override.requestRollout instead. UUID to request a rollout of the environment."
  type        = string
  default     = null
}
