variable "aws_region" {
  description = "The AWS region where the resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "The AWS profile to use for authentication."
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources created."
  type        = map(string)
}

variable "name_prefix" {
  description = "A prefix to add to all resource names."
  type        = string
}

variable "license_key" {
  description = "Materialize license key"
  type        = string
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

variable "ingress_cidr_blocks" {
  description = "List of CIDR blocks to allow access to materialize."
  type        = list(string)
  default     = ["0.0.0.0/0"]
  nullable    = false
}
