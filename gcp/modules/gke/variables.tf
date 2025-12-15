variable "project_id" {
  description = "The ID of the project where resources will be created"
  type        = string
  nullable    = false
}

variable "region" {
  description = "The region where resources will be created"
  type        = string
  nullable    = false
}

# TODO: add length validation on prefix
# account_id   = "${var.prefix}-materialize-sa" length should be between [6-30]
variable "prefix" {
  description = "Prefix to be used for resource names"
  type        = string
  nullable    = false
}

variable "network_name" {
  description = "The name of the VPC network"
  type        = string
  nullable    = false
}

variable "subnet_name" {
  description = "The name of the subnet"
  type        = string
  nullable    = false
}

variable "namespace" {
  description = "The namespace where the Materialize Operator will be installed"
  type        = string
  nullable    = false
}

variable "networking_mode" {
  description = "The networking mode for the GKE cluster"
  type        = string
  default     = "VPC_NATIVE"
  validation {
    condition     = contains(["VPC_NATIVE", "ROUTES"], var.networking_mode)
    error_message = "Networking mode must be either VPC_NATIVE or ROUTES"
  }
}

variable "cluster_secondary_range_name" {
  description = "The name of the secondary range to use for pods"
  type        = string
  default     = "pods"
  nullable    = false
}

variable "services_secondary_range_name" {
  description = "The name of the secondary range to use for services"
  type        = string
  default     = "services"
  nullable    = false
}

variable "release_channel" {
  description = "The release channel for the GKE cluster"
  type        = string
  default     = "REGULAR"
  validation {
    condition     = contains(["UNSPECIFIED", "RAPID", "REGULAR", "STABLE", "EXTENDED"], var.release_channel)
    error_message = "Release channel must be one of UNSPECIFIED, RAPID, REGULAR, STABLE, or EXTENDED"
  }
}

variable "horizontal_pod_autoscaling_disabled" {
  description = "Whether to disable horizontal pod autoscaling"
  type        = bool
  default     = false
  nullable    = false
}

variable "http_load_balancing_disabled" {
  description = "Whether to disable HTTP load balancing"
  type        = bool
  default     = false
  nullable    = false
}

variable "gce_persistent_disk_csi_driver_enabled" {
  description = "Whether to enable the GCE persistent disk CSI driver"
  type        = bool
  default     = true
  nullable    = false
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default     = {}
}

# GCP manages this CIDR block when not provided as input
variable "master_ipv4_cidr_block" {
  description = "The IP range in CIDR notation to use for the hosted master network. This range must not overlap with any other ranges in use within the cluster's network."
  type        = string
  default     = null
  nullable    = true
}

# modify this to restrict public access to master endpoint from specific IP ranges
variable "k8s_apiserver_authorized_networks" {
  description = "List of CIDR blocks to allow access to the Kubernetes master endpoint. Each entry should have cidr_block and display_name. Defaults to 0.0.0.0/0 to allow access from anywhere."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [{
    cidr_block   = "0.0.0.0/0"
    display_name = "Authorized networks"
  }]
  nullable = false
}
