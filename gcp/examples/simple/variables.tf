variable "project_id" {
  description = "The ID of the project where resources will be created"
  type        = string
}

variable "region" {
  description = "The region where resources will be created"
  type        = string
  default     = "us-central1"
}

variable "zones" {
  description = <<-EOT
    List of zones within the region where GKE nodes can be created (e.g., ["us-central1-a", "us-central1-b"]).
    If not specified (null), GKE will use all available zones in the region.

    IMPORTANT: All zones must be within the specified region. For example, if region is "us-central1",
    valid zones are "us-central1-a", "us-central1-b", "us-central1-c", "us-central1-f".
    Using zones from a different region will cause deployment failures.

    Multi-zone considerations:
    - GCP Persistent Disks are zonal resources, meaning a PD can only be attached to a node in the same zone.
    - The default storage class 'standard-rwo' uses 'WaitForFirstConsumer' binding mode, which ensures
      PDs are created in the same zone as the scheduled pod.
    - For high availability, use at least 2 zones. For cost optimization, you can limit to fewer zones.

    Example:
      zones = ["us-central1-a", "us-central1-b", "us-central1-c"]  # Multi-zone HA
      zones = ["us-central1-a"]  # Single-zone (lower cost, no zone redundancy)
      zones = null  # Use all zones in the region (default)
  EOT
  type        = list(string)
  default     = null
  nullable    = true

  validation {
    condition     = var.zones == null || length(var.zones) > 0
    error_message = "If specified, zones must contain at least one zone."
  }
}

variable "labels" {
  description = "Labels to apply to resources created."
  type        = map(string)
}

variable "name_prefix" {
  description = "Prefix to be used for resource names"
  type        = string
  default     = "materialize"
}

variable "license_key" {
  description = "Materialize license key"
  type        = string
  default     = null
  sensitive   = true
}

variable "ingress_cidr_blocks" {
  description = "The CIDR blocks that are allowed to reach the Load Balancer."
  type        = list(string)
  default     = ["0.0.0.0/0"]
  nullable    = true

  validation {
    condition = var.ingress_cidr_blocks == null || alltrue([
      for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All ingress_cidr_blocks must be valid CIDR notation (e.g., '10.0.0.0/8' or '0.0.0.0/0')."
  }
}

variable "k8s_apiserver_authorized_networks" {
  description = "The CIDR blocks that are allowed to reach the Kubernetes master endpoint."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [{
    cidr_block   = "0.0.0.0/0"
    display_name = "Default Placeholder for authorized networks"
  }]
  nullable = false

  validation {
    condition = alltrue([
      for network in var.k8s_apiserver_authorized_networks : can(cidrhost(network.cidr_block, 0))
    ])
    error_message = "All k8s_apiserver_authorized_networks must be valid CIDR notation (e.g., '10.0.0.0/8' or '0.0.0.0/0')."
  }
}

variable "internal_load_balancer" {
  description = "Whether to use an internal load balancer"
  type        = bool
  default     = true
}

variable "crd_version" {
  description = "CRD API version to use for the Materialize instance (v1alpha1 or v1alpha2). We recommend v1alpha2, but default to v1alpha1 for backwards compatibility. We will change this default in an upcoming major release."
  type        = string
  default     = "v1alpha1"
  nullable    = false

  validation {
    condition     = contains(["v1alpha1", "v1alpha2"], var.crd_version)
    error_message = "CRD version must be either 'v1alpha1' or 'v1alpha2'"
  }
}

variable "enable_observability" {
  description = "Enable Prometheus and Grafana monitoring stack for Materialize"
  type        = bool
  default     = false
}
