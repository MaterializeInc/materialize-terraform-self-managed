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

# System nodepool variables
variable "system_nodepool_instance_types" {
  description = "Instance types for the system nodepool"
  type        = list(string)
  default     = ["t3.medium"]
  nullable    = false
}

variable "system_nodepool_desired_size" {
  description = "Desired number of nodes in the system nodepool"
  type        = number
  default     = 2
  nullable    = false
}

variable "system_nodepool_min_size" {
  description = "Minimum number of nodes in the system nodepool"
  type        = number
  default     = 1
  nullable    = false
}

variable "system_nodepool_max_size" {
  description = "Maximum number of nodes in the system nodepool"
  type        = number
  default     = 2
  nullable    = false
}

variable "system_nodepool_capacity_type" {
  description = "Capacity type for system nodepool (ON_DEMAND or SPOT)"
  type        = string
  default     = "ON_DEMAND"
  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.system_nodepool_capacity_type)
    error_message = "Capacity type must be either ON_DEMAND or SPOT."
  }
}
