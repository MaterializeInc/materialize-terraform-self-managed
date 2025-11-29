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
  description = "UUID to force a rollout"
  type        = string
  default     = "00000000-0000-0000-0000-000000000001"
}

variable "request_rollout" {
  description = "UUID to request a rollout"
  type        = string
  default     = "00000000-0000-0000-0000-000000000001"
}
