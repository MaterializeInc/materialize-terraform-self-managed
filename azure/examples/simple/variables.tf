variable "subscription_id" {
  description = "The ID of the Azure subscription"
  type        = string
}

variable "resource_group_name" {
  description = "The name of the resource group which will be created."
  type        = string
}

variable "location" {
  description = "The location of the Azure subscription"
  type        = string
  default     = "westus2"
}

variable "name_prefix" {
  description = "The prefix of the Azure subscription"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources created."
  type        = map(string)
}

variable "ingress_cidr_blocks" {
  description = "CIDR blocks that can reach the Azure LoadBalancer frontends."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition = alltrue([
      for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All ingress_cidr_blocks must be valid CIDR notation (e.g., '10.0.0.0/8' or '0.0.0.0/0')."
  }
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

variable "k8s_apiserver_authorized_networks" {
  description = "List of authorized IP ranges that can access the Kubernetes API server when public access is available. Defaults to ['0.0.0.0/0'] (allow all). For production, restrict to specific IPs (e.g., ['203.0.113.0/24'])"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Explicit default: allow all IPs
  nullable    = true

  validation {
    condition = (
      var.k8s_apiserver_authorized_networks == null ||
      alltrue([
        for cidr in var.k8s_apiserver_authorized_networks :
        can(cidrhost(cidr, 0))
      ])
    )
    error_message = "All k8s_apiserver_authorized_networks must be valid CIDR blocks (e.g., '203.0.113.0/24')."
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

variable "materialize_version" {
  description = "Materialize release for both the operator Helm chart and environmentd, which must not drift. Null uses each module's default."
  type        = string
  default     = null
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
