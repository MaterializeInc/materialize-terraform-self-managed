variable "project_id" {
  description = "The ID of the project where resources will be created"
  type        = string
}

variable "region" {
  description = "The region where resources will be created"
  type        = string
}

# TODO: add length validation on prefix
# account_id   = "${var.prefix}-materialize-sa" length should be between [6-30]
variable "prefix" {
  description = "Prefix to be used for resource names"
  type        = string
}

variable "network_name" {
  description = "The name of the VPC network"
  type        = string
}

variable "subnet_name" {
  description = "The name of the subnet"
  type        = string
}

variable "namespace" {
  description = "The namespace where the GKE cluster will be created"
  type        = string
}

variable "networking_mode" {
  description = "The networking mode for the GKE cluster"
  type        = string
  default     = "VPC_NATIVE"
}

variable "cluster_secondary_range_name" {
  description = "The name of the secondary range to use for pods"
  type        = string
  default     = "pods"
}

variable "services_secondary_range_name" {
  description = "The name of the secondary range to use for services"
  type        = string
  default     = "services"
}

variable "release_channel" {
  description = "The release channel for the GKE cluster"
  type        = string
  default     = "REGULAR"
}

variable "horizontal_pod_autoscaling_disabled" {
  description = "Whether to disable horizontal pod autoscaling"
  type        = bool
  default     = false
}

variable "http_load_balancing_disabled" {
  description = "Whether to disable HTTP load balancing"
  type        = bool
  default     = false
}

variable "gce_persistent_disk_csi_driver_enabled" {
  description = "Whether to enable the GCE persistent disk CSI driver"
  type        = bool
  default     = true
}
