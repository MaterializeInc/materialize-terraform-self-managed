variable "profile" {
  description = "AWS profile to use for authentication"
  type        = string
}

variable "region" {
  description = "AWS region to deploy resources in"
  type        = string
}

variable "cluster_name" {
  description = "Name prefix for the EKS cluster"
  type        = string
}

variable "cluster_endpoint" {
  description = "Endpoint for the EKS cluster"
  type        = string
}

variable "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate authority data for the EKS cluster"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}


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

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
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

variable "oidc_provider_arn" {
  description = "OIDC provider ARN for the EKS cluster"
  type        = string
}

variable "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster"
  type        = string
}

variable "operator_namespace" {
  description = "Namespace for the Materialize operator"
  type        = string
}

variable "install_materialize_instance" {
  description = "Flag to indicate if Materialize instance should be installed"
  type        = bool
}

variable "instance_name" {
  description = "Name of the Materialize instance"
  type        = string
}

variable "instance_namespace" {
  description = "Namespace for the Materialize instance"
  type        = string
}

variable "swap_enabled" {
  description = "Enable swap"
  type        = bool
}

variable "database_username" {
  description = "Username for the Materialize database"
  type        = string
}

variable "database_password" {
  description = "Password for the Materialize database"
  type        = string
}

variable "database_endpoint" {
  description = "Endpoint for the Materialize database"
  type        = string
}

variable "database_name" {
  description = "Name of the Materialize database"
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

variable "subnet_ids" {
  description = "List of subnet IDs for the NLB"
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID for the NLB"
  type        = string
}

variable "enable_cross_zone_load_balancing" {
  description = "Enable cross-zone load balancing for the NLB"
  type        = bool
}
