variable "project_id" {
  description = "The ID of the project where resources will be created"
  type        = string
}

variable "region" {
  description = "The region where resources will be created"
  type        = string
  default     = "us-east1"
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

variable "force_rollout" {
  description = "UUID to force a rollout"
  type        = string
  default     = "00000000-0000-0000-0000-000000000001"
}

variable "request_rollout" {
  description = "UUID to request a rollout"
  type        = string
  default     = "00000000-0000-0000-0000-000000000001"
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

variable "enable_observability" {
  description = "Enable the monitoring stack for Materialize — Loki, Thanos, Grafana, Alertmanager, and Alloy"
  type        = bool
  default     = true
}

variable "datapath_provider" {
  description = "The datapath provider (CNI) for the GKE cluster. ADVANCED_DATAPATH is GKE Dataplane V2 (eBPF-based, enforces Kubernetes NetworkPolicy natively). DATAPATH_PROVIDER_UNSPECIFIED and LEGACY_DATAPATH use the legacy GKE CNI, which silently ignores NetworkPolicy resources. GKE cannot change the datapath provider on an existing cluster: changing this forces the cluster to be rebuilt."
  type        = string
  default     = "ADVANCED_DATAPATH"
  nullable    = false

  validation {
    condition     = contains(["ADVANCED_DATAPATH", "LEGACY_DATAPATH", "DATAPATH_PROVIDER_UNSPECIFIED"], var.datapath_provider)
    error_message = "Datapath provider must be one of ADVANCED_DATAPATH, LEGACY_DATAPATH, or DATAPATH_PROVIDER_UNSPECIFIED"
  }
}

variable "materialize_version" {
  description = "Materialize release for both the operator Helm chart and environmentd, which must not drift. Null uses each module's default."
  type        = string
  default     = null
}

variable "enable_node_upgrade_rollout_trigger" {
  description = "Trigger rollouts of Materialize instances when GKE upgrades the node pools they run on, moving their pods to the replacement nodes gracefully instead of letting GKE evict them."
  type        = bool
  default     = true
  nullable    = false
}

variable "grafana_host" {
  description = "Hostname to reach Grafana on. Optional: the load balancer answers on an IP regardless, but Grafana builds share links, alert notification links, and OAuth redirect URIs from `root_url`, which is only correct once this is set. DNS for the name is yours to create."
  type        = string
  default     = null
}

variable "grafana_allow_public_access" {
  description = <<-EOT
    Acknowledge a Grafana load balancer that is public (`internal_load_balancer = false`) with an
    unrestricted allowlist (`ingress_cidr_blocks` containing `0.0.0.0/0` or `::/0`).

    The monitoring module refuses that combination at plan time, and deliberately: nothing
    terminates TLS, Grafana has no identity provider until you configure one, and every datasource
    behind it reads every metric in Thanos and every log in the tenant — so the generated admin
    password is the whole of the access control.

    Leave this `false` and narrow `ingress_cidr_blocks`, or keep the load balancers internal. Set it
    only when the allowlist is genuinely enforced somewhere Terraform cannot see, such as an
    upstream firewall or an authenticating proxy. It is set by the infrastructure test harness,
    whose clusters are ephemeral and whose runners need a public address.
  EOT
  type        = bool
  default     = false
  nullable    = false
}
