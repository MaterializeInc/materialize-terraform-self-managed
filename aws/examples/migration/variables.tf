# =============================================================================
# Migration Reference Variables
# =============================================================================
#
# Update these variables to match your existing infrastructure.
# Set values in terraform.tfvars (see terraform.tfvars.example).
#
# =============================================================================

# -----------------------------------------------------------------------------
# AWS Configuration
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# Core Configuration
# -----------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix used for all resource names (must match existing)"
  type        = string
}

variable "license_key" {
  description = "Materialize license key"
  type        = string
  sensitive   = true
}

variable "environment" {
  description = "Environment name from the old module (e.g., 'dev', 'staging', 'prod'). Used to construct the S3 persist path to match existing data."
  type        = string
}

# -----------------------------------------------------------------------------
# Materialize Instance Configuration
# -----------------------------------------------------------------------------

variable "materialize_instance_name" {
  description = "Name of your existing Materialize instance. Run: kubectl get materialize -A"
  type        = string
}

variable "materialize_instance_namespace" {
  description = "Kubernetes namespace for the Materialize instance"
  type        = string
  default     = "materialize-environment"
}

variable "environmentd_image_ref" {
  description = "Materialize environmentd image reference. Must match your existing version."
  type        = string
  default     = "materialize/environmentd:v26.5.1"
}

# -----------------------------------------------------------------------------
# Migration Secrets
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# VPC / Networking
# -----------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC (must match existing)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones (must match existing)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (must match existing)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (must match existing)"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "single_nat_gateway" {
  description = "Use a single NAT gateway instead of one per AZ. Old module default was false (one per AZ)."
  type        = bool
  default     = false
}

variable "enable_vpc_endpoints" {
  description = "Whether to enable VPC endpoints"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# EKS Cluster
# -----------------------------------------------------------------------------

variable "cluster_version" {
  description = "Kubernetes version for EKS cluster (must match existing)"
  type        = string
  default     = "1.32"
}

# -----------------------------------------------------------------------------
# Base Node Group (system workloads)
# -----------------------------------------------------------------------------

variable "base_instance_types" {
  description = "Instance types for the base/system node group (old default: r7g.xlarge)"
  type        = list(string)
  default     = ["r7g.xlarge"]
}

variable "base_node_min_size" {
  description = "Minimum number of nodes in the base node group (old default: 1)"
  type        = number
  default     = 1
}

variable "base_node_max_size" {
  description = "Maximum number of nodes in the base node group (old default: 4)"
  type        = number
  default     = 4
}

variable "base_node_desired_size" {
  description = "Desired number of nodes in the base node group (old default: 2)"
  type        = number
  default     = 2
}

# -----------------------------------------------------------------------------
# Materialize Node Group
# -----------------------------------------------------------------------------

variable "mz_instance_types" {
  description = "Instance types for the Materialize node group"
  type        = list(string)
  default     = ["r7gd.2xlarge"]
}

variable "mz_node_min_size" {
  description = "Minimum number of nodes in the Materialize node group (old default: 1)"
  type        = number
  default     = 1
}

variable "mz_node_max_size" {
  description = "Maximum number of nodes in the Materialize node group (old default: 4)"
  type        = number
  default     = 4
}

variable "mz_node_desired_size" {
  description = "Desired number of nodes in the Materialize node group (old default: 1)"
  type        = number
  default     = 1
}

# -----------------------------------------------------------------------------
# Database (RDS)
# -----------------------------------------------------------------------------

variable "postgres_version" {
  description = "PostgreSQL version for RDS (must match existing)"
  type        = string
  default     = "17"
}

variable "db_instance_class" {
  description = "RDS instance class (must match existing)"
  type        = string
  default     = "db.m6i.large"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB for RDS (must match existing)"
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Maximum allocated storage in GB for RDS autoscaling"
  type        = number
  default     = 100
}

variable "db_multi_az" {
  description = "Whether to enable Multi-AZ for RDS"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# TLS Configuration
# -----------------------------------------------------------------------------

variable "use_self_signed_cluster_issuer" {
  description = "Whether to enable TLS using the self-signed cluster issuer. Must match your old module's setting to preserve TLS configuration."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Access Control
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# Rollout Configuration (usually leave as defaults)
# -----------------------------------------------------------------------------

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
