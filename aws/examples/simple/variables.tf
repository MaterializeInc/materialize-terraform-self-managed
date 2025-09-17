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

variable "install_materialize_instance" {
  description = "Whether to install the Materialize instance. Default is false as it requires the Kubernetes cluster to be created first."
  type        = bool
  default     = false
}

variable "license_key" {
  description = "Materialize license key"
  type        = string
  default     = null
  sensitive   = true
}
