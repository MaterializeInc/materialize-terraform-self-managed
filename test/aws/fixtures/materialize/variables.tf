# AWS Provider Variables
variable "region" {
  description = "AWS region to deploy resources in"
  type        = string
}

variable "profile" {
  description = "AWS profile to use for authentication (optional for OIDC)"
  type        = string
  default     = null
}

# Network Variables
variable "vpc_id" {
  description = "ID of the VPC where resources will be created"
  type        = string
}

variable "subnet_ids" {
  description = "List of private subnet IDs for the resources"
  type        = list(string)
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
}

variable "cluster_enabled_log_types" {
  description = "List of desired control plane logging to enable"
  type        = list(string)
}

variable "enable_cluster_creator_admin_permissions" {
  description = "To add the current caller identity as an administrator"
  type        = bool
}

variable "materialize_node_ingress_cidrs" {
  description = "List of CIDR blocks to allow ingress from for Materialize ports (HTTP 6876, pgwire 6875, health checks 8080)."
  type        = list(string)
}

variable "min_nodes" {
  description = "Minimum number of nodes in the node group"
  type        = number
}

variable "max_nodes" {
  description = "Maximum number of nodes in the node group"
  type        = number
}

variable "desired_nodes" {
  description = "Desired number of nodes in the node group"
  type        = number
}

variable "instance_types" {
  description = "List of instance types for the node group"
  type        = list(string)
}

variable "capacity_type" {
  description = "Type of capacity associated with the EKS Node Group. Valid values: ON_DEMAND, SPOT"
  type        = string
}

variable "swap_enabled" {
  description = "Enable swap for nodes"
  type        = bool
}

variable "node_labels" {
  description = "Labels to apply to the node group"
  type        = map(string)
}

variable "iam_role_use_name_prefix" {
  description = "Use name prefix for IAM roles"
  type        = bool
}

# Database Variables
variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
}

variable "allocated_storage" {
  description = "Initial allocated storage in GB"
  type        = number
}

variable "max_allocated_storage" {
  description = "Maximum allocated storage in GB"
  type        = number
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment"
  type        = bool
}

variable "database_name" {
  description = "Name of the database"
  type        = string
}

variable "database_username" {
  description = "Username for the database"
  type        = string
}

variable "database_password" {
  description = "Password for the database"
  type        = string
  sensitive   = true
}

variable "maintenance_window" {
  description = "Maintenance window for the database"
  type        = string
}

variable "backup_window" {
  description = "Backup window for the database"
  type        = string
}

variable "backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
}

# Materialize Variables
variable "bucket_lifecycle_rules" {
  description = "List of lifecycle rules for the S3 bucket"
  type = list(object({
    id                                 = string
    enabled                            = bool
    prefix                             = string
    transition_days                    = number
    transition_storage_class           = string
    noncurrent_version_expiration_days = number
  }))
}

variable "bucket_force_destroy" {
  description = "Enable force destroy for the S3 bucket"
  type        = bool
}

variable "enable_bucket_versioning" {
  description = "Enable versioning for the S3 bucket"
  type        = bool
}

variable "enable_bucket_encryption" {
  description = "Enable server-side encryption for the S3 bucket"
  type        = bool
}

variable "cert_manager_install_timeout" {
  description = "Cert-manager install timeout in seconds"
  type        = number
}

variable "cert_manager_chart_version" {
  description = "Cert-manager chart version"
  type        = string
}

variable "cert_manager_namespace" {
  description = "Cert-manager namespace"
  type        = string
}

variable "operator_namespace" {
  description = "Namespace for the Materialize operator"
  type        = string
}

variable "instance_name" {
  description = "Name of the Materialize instance"
  type        = string
}

variable "instance_namespace" {
  description = "Namespace for the Materialize instance"
  type        = string
}

variable "external_login_password_mz_system" {
  description = "Password for external login to the Materialize instance"
  type        = string
  sensitive   = true
}

variable "license_key" {
  description = "Materialize license key"
  type        = string
  default     = null
  sensitive   = true
}

variable "enable_cross_zone_load_balancing" {
  description = "Enable cross-zone load balancing for the NLB"
  type        = bool
}

variable "internal" {
  description = "Whether the NLB is internal only. Defaults to false (public) to allow external access to Materialize. Set to true for VPC-only access."
  type        = bool
  default     = false
  nullable    = false
}

variable "ingress_cidr_blocks" {
  description = "List of CIDR blocks to allow ingress to the NLB Security Group."
  type        = list(string)
  nullable    = false
}

variable "nlb_subnet_ids" {
  description = "List of subnet IDs for the NLB"
  type        = list(string)
  nullable    = false
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks to allow public access to the EKS cluster endpoint"
  type        = list(string)
  nullable    = false
}

# Common Variables
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
}
