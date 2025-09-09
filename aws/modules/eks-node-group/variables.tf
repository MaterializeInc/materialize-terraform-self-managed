variable "cluster_name" {
  description = "Name of the EKS cluster to attach the node group to."
  type        = string
  nullable    = false
}

variable "subnet_ids" {
  description = "List of subnet IDs for the node group."
  type        = list(string)
  nullable    = false
}

variable "node_group_name" {
  description = "Name of the node group."
  type        = string
  nullable    = false
}

variable "desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 1
  nullable    = false
}

variable "min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 1
  nullable    = false
}

variable "max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 4
  nullable    = false
}

variable "instance_types" {
  description = <<EOF
Instance types for worker nodes.

Recommended Configuration for Running Materialize with disk:
- Tested instance types: `r6gd`, `r7gd` families (ARM-based Graviton instances)
- Enable disk setup when using `r7gd`
- Note: Ensure instance store volumes are available and attached to the nodes for optimal performance with disk-based workloads.
EOF
  type        = list(string)
  default     = ["r7gd.2xlarge"]
  nullable    = false
}

variable "capacity_type" {
  description = "Capacity type for worker nodes (ON_DEMAND or SPOT)."
  type        = string
  default     = "ON_DEMAND"
  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "Capacity type must be either ON_DEMAND or SPOT."
  }
}

variable "ami_type" {
  description = "AMI type for the node group."
  type        = string
  default     = "AL2023_ARM_64_STANDARD"
  nullable    = false
}

variable "labels" {
  description = "Labels to apply to the node group."
  type        = map(string)
  default     = {}
}

variable "enable_disk_setup" {
  description = "Whether to enable disk setup using the bootstrap script"
  type        = bool
  default     = true
  nullable    = false
}

variable "cluster_service_cidr" {
  description = "The CIDR block for the cluster service"
  type        = string
  nullable    = false
}

variable "cluster_primary_security_group_id" {
  description = "The ID of the primary security group for the cluster"
  type        = string
  nullable    = false
}

variable "iam_role_use_name_prefix" {
  description = "Use name prefix for IAM roles"
  type        = bool
  default     = true
}
