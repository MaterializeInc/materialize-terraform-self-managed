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
  nullable    = false

  validation {
    condition = alltrue([
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

variable "enable_provider_metrics" {
  description = <<-EOT
    Pull Cloud Monitoring metrics for the Materialize database and persist bucket, the monitoring
    stack's own buckets and Grafana database, the region's Compute Engine quota, the load balancers
    in the deployment's network, and the Cloud NAT gateway into the monitoring stack. Grants the Alloy gateway's service account
    `roles/monitoring.viewer`.
  EOT
  type        = bool
  default     = false
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
  description = "Hostname to reach Grafana on. Optional: the load balancer answers on an IP regardless, but Grafana builds share links, alert notification links, and OAuth redirect URIs from `root_url`, which is only correct once this is set. DNS for the name is yours to create. With `dns` set, leave this unset; Grafana's hostname comes from `dns`."
  type        = string
  default     = null

  validation {
    condition     = var.grafana_host == null || var.dns == null
    error_message = "Set grafana_host or dns, not both: with dns, Grafana's hostname is dns.subdomains.grafana under the stem domain."
  }
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

variable "dns" {
  description = <<-EOT
    An existing Cloud DNS managed zone to put the console, balancerd and Grafana hostnames in.
    They sit under `stem_domain`, which defaults to the zone's domain: the console on
    `stem_domain` itself, and balancerd and Grafana on subdomains of those names. `subdomains`
    overrides any of them, keyed `console`, `balancerd` and `grafana`, with `"@"` for the stem
    itself. The example creates the console and balancerd records. It does not create Grafana's,
    because the address of Grafana's load balancer may not be known on the first apply; point
    that one at the `grafana_load_balancer_address` output. The zone itself is never created or
    changed.

    With `letsencrypt` set, cert-manager answers ACME DNS-01 challenges in the zone, and a Let's
    Encrypt issuer signs the console and balancerd certificates while the internal ones stay
    self-signed. The issuer starts on Let's Encrypt staging, as
    `<name_prefix>-letsencrypt-staging`; once staging has issued every certificate, set
    `acme_server_prod = true` and apply again.
  EOT
  type = object({
    zone_name       = string
    zone_project_id = optional(string)
    stem_domain     = optional(string)
    subdomains      = optional(map(string), {})
    letsencrypt = optional(object({
      acme_email       = string
      acme_server_prod = optional(bool, false)
    }))
  })
  default = null

  validation {
    condition     = alltrue([for key in keys(try(var.dns.subdomains, {})) : contains(["console", "balancerd", "grafana"], key)])
    error_message = "dns.subdomains keys must be console, balancerd or grafana."
  }
}
