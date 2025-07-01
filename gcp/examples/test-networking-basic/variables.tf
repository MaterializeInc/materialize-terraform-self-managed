variable "project_id" {
  description = "The ID of the project where resources will be created"
  type        = string
}

variable "region" {
  description = "The region where resources will be created"
  type        = string
  default     = "us-central1"
}

variable "prefix" {
  description = "Prefix to be used for resource names"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.100.0.0/20"
}

variable "pods_cidr" {
  description = "CIDR block for Kubernetes pods"
  type        = string
  default     = "10.104.0.0/14"
}

variable "services_cidr" {
  description = "CIDR block for Kubernetes services"
  type        = string
  default     = "10.108.0.0/20"
}