variable "region" {
  description = "AWS region"
  type        = string
}

variable "cluster_name" {
  description = "Name prefix for the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where EKS will be created"
  type        = string
}

variable "subnet_ids" {
  description = "List of private subnet IDs for the EKS cluster"
  type        = list(string)
}

variable "cluster_enabled_log_types" {
  description = "List of desired control plane logging to enable"
  type        = list(string)
}

variable "enable_cluster_creator_admin_permissions" {
  description = "To add the current caller identity as an administrator"
  type        = bool
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
}

variable "skip_node_group" {
  description = "Skip creating the EKS node group"
  type        = bool
}

variable "skip_aws_lbc" {
  description = "Skip deploying AWS Load Balancer Controller"
  type        = bool
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

variable "disk_setup_enabled" {
  description = "Enable disk setup for nodes"
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
