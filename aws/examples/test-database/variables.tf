variable "profile" {
  description = "AWS profile to use for authentication"
  type        = string
}

variable "region" {
  description = "AWS region to deploy resources in"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the database will be created"
  type        = string
}

variable "database_subnet_ids" {
  description = "List of subnet IDs for the database"
  type        = list(string)
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

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_security_group_id" {
  description = "Security group ID of the EKS cluster"
  type        = string
}

variable "node_security_group_id" {
  description = "Security group ID of the EKS nodes"
  type        = string
}

variable "eks_clusters" {
  description = "List of EKS clusters with their security group IDs"
  type = list(object({
    cluster_name              = string
    cluster_security_group_id = string
    node_security_group_id    = string
  }))
  default = []
}
