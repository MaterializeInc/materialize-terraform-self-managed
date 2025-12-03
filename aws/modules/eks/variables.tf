variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  nullable    = false
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  nullable    = false
  default     = "1.32"
}

variable "vpc_id" {
  description = "ID of the VPC where EKS will be created"
  type        = string
  nullable    = false
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EKS"
  type        = list(string)
  nullable    = false
}

variable "cluster_enabled_log_types" {
  description = "List of desired control plane logging to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  nullable    = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_cluster_creator_admin_permissions" {
  description = "To add the current caller identity as an administrator"
  type        = bool
  default     = true
  nullable    = false
}

variable "iam_role_use_name_prefix" {
  description = "Use name prefix for IAM roles"
  type        = bool
  default     = true
  nullable    = false
}

variable "materialize_node_ingress_cidr" {
  description = "List of CIDR blocks to allow ingress from for Materialize ports (HTTP 6876, pgwire 6875, health checks 8080)."
  type        = list(string)
  nullable    = false
}
