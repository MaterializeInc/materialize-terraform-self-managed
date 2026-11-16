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

variable "enable_provider_metrics" {
  description = <<-EOT
    Pull Azure Monitor metrics for the Materialize database and persist storage account, the
    monitoring stack's own storage account and Grafana database, the AKS cluster's autoscaler, node
    VMs and load balancers, and the NAT gateway into the monitoring stack. Creates an identity for
    the Alloy gateway with Monitoring Reader on those resources and the cluster's node resource
    group only.
  EOT
  type        = bool
  default     = false
}

variable "materialize_version" {
  description = "Materialize release for both the operator Helm chart and environmentd, which must not drift. Null uses each module's default."
  type        = string
  default     = null
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
    An existing Azure DNS zone to put the console, balancerd and Grafana hostnames in, named by
    `zone_name` (such as example.com) and `zone_resource_group_name`, in the subscription the
    azurerm provider uses. The hostnames sit under `stem_domain`, which defaults to the zone's
    domain: the console on `stem_domain` itself, and balancerd and Grafana on subdomains of
    those names. `subdomains` overrides any of them, keyed `console`, `balancerd` and `grafana`,
    with `"@"` for the stem itself. The example creates the console and balancerd records. It
    does not create Grafana's, because the address of Grafana's load balancer may not be known
    on the first apply; point that one at the `grafana_load_balancer_address` output. The zone
    itself is never created or changed.

    With `letsencrypt` set, cert-manager answers ACME DNS-01 challenges in the zone, and a Let's
    Encrypt issuer signs the console and balancerd certificates while the internal ones stay
    self-signed. The issuer starts on Let's Encrypt staging, as
    `<name_prefix>-letsencrypt-staging`; once staging has issued every certificate, set
    `acme_server_prod = true` and apply again.
  EOT
  type = object({
    zone_name                = string
    zone_resource_group_name = string
    stem_domain              = optional(string)
    subdomains               = optional(map(string), {})
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
