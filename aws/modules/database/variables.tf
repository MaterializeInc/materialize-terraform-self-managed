variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  nullable    = false
}

variable "postgres_version" {
  description = "Version of PostgreSQL to use"
  type        = string
  default     = "15"
  nullable    = false
}

variable "instance_class" {
  description = "Instance class for the RDS instance"
  type        = string
  nullable    = false
}

variable "allocated_storage" {
  description = "Allocated storage for the RDS instance (in GB)"
  type        = number
  default     = 50
  nullable    = false
}

variable "max_allocated_storage" {
  description = "Maximum storage for autoscaling (in GB)"
  type        = number
  default     = 100
  nullable    = false
}

variable "database_name" {
  description = "Name of the database to create"
  type        = string
  nullable    = false
}

variable "database_username" {
  description = "Username for the database"
  type        = string
  nullable    = false
}

variable "database_password" {
  description = "Password for the database"
  type        = string
  sensitive   = true
}

variable "multi_az" {
  description = "Enable multi-AZ deployment"
  type        = bool
  default     = false
  nullable    = false
}

variable "database_subnet_ids" {
  description = "List of subnet IDs for the database"
  type        = list(string)
  nullable    = false
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
  nullable    = false
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  nullable    = false
}

variable "cluster_security_group_id" {
  description = "Security group ID of the EKS cluster"
  type        = string
  nullable    = false
}

variable "node_security_group_id" {
  description = "Security group ID of the EKS nodes"
  type        = string
  nullable    = false
}

variable "backup_retention_period" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
  nullable    = false
}

variable "backup_window" {
  description = "Preferred backup window"
  type        = string
  default     = "03:00-06:00"
  nullable    = false
}

variable "maintenance_window" {
  description = "Preferred maintenance window"
  type        = string
  default     = "Mon:00:00-Mon:03:00"
  nullable    = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "kms_key_id" {
  description = "The ARN for the KMS encryption key. If not specified and create_kms_key is false, the default AWS managed key will be used."
  type        = string
  default     = null
}

variable "create_kms_key" {
  description = "Whether to create a new KMS key for RDS encryption. If false and kms_key_id is not specified, the default AWS managed key will be used."
  type        = bool
  default     = false
}

variable "kms_key_deletion_window_in_days" {
  description = "The waiting period, specified in number of days, after which AWS KMS deletes the KMS key. Valid values are 7-30 days."
  type        = number
  default     = 30
}

variable "kms_key_enable_rotation" {
  description = "Specifies whether key rotation is enabled for the KMS key."
  type        = bool
  default     = true
}

