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

variable "eks_allowed_ingress_cidrs" {
  description = "Additional CIDR blocks to allow ingress to EKS nodes for Materialize ports (6875, 6876, 8080). For production use, set this to [] (empty list) to only allow traffic from within the VPC, or specify specific CIDR ranges (e.g., VPN, peered networks)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  nullable    = false
}
