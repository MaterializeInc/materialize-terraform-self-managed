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

variable "license_key" {
  description = "Materialize license key"
  type        = string
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
  description = "List of CIDR blocks to allow access to materialize Load Balancers. Only applied when Load Balancer is public."
  type        = list(string)
  default     = ["0.0.0.0/0"]
  nullable    = true

  validation {
    condition     = var.ingress_cidr_blocks == null || alltrue([for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All CIDR blocks must be valid IPv4 CIDR notation (e.g., '10.0.0.0/16' or '0.0.0.0/0')."
  }
}

variable "k8s_apiserver_authorized_networks" {
  description = "List of CIDR blocks to allow public access to the EKS cluster endpoint"
  type        = list(string)
  nullable    = false
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for cidr in var.k8s_apiserver_authorized_networks : can(cidrhost(cidr, 0))])
    error_message = "All k8s_apiserver_authorized_networks valid IPv4 CIDR notation (e.g., '10.0.0.0/16' or '0.0.0.0/0')."
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
    Pull CloudWatch metrics for the Materialize database and persist bucket, the monitoring stack's
    own buckets, Grafana database and Grafana load balancer, the EKS cluster's nodes and node groups,
    and the VPC's NAT gateways into the monitoring stack. Creates a read-only IRSA role for the Alloy
    gateway.

    Off by default: CloudWatch bills each `GetMetricStatistics` call, about 44 every five minutes for
    this example with its one NAT gateway: 6 per NAT gateway and 8 for Grafana's load balancer among
    them. The cluster's pull adds one more for the account's vCPU usage, seven `ListMetrics` calls,
    and `GetMetricData` billed per metric: three per node and four per managed node group.
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
  description = "Hostname to reach Grafana on. Optional: the load balancer answers on its own DNS name regardless, but Grafana builds share links, alert notification links, and OAuth redirect URIs from `root_url`, which is only correct once this is set. DNS for the name is yours to create. With `dns` set, leave this unset; Grafana's hostname comes from `dns`."
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
    An existing Route 53 hosted zone to put the console, balancerd and Grafana hostnames in.
    They sit under `stem_domain`, which defaults to the zone's domain: the console on
    `stem_domain` itself, and balancerd and Grafana on subdomains of those names. `subdomains`
    overrides any of them, keyed `console`, `balancerd` and `grafana`, with `"@"` for the stem
    itself. The example creates the console and balancerd records, and Grafana's when
    `enable_observability` is true. The zone itself is never created or changed.

    The load balancers answer on DNS names, so every record is a CNAME, and a CNAME cannot sit
    at the zone's apex. With the console on `"@"`, set `stem_domain` below the apex, such as
    `mz.example.com` in the zone `example.com`, or move the console off `"@"` with `subdomains`.

    With `letsencrypt` set, cert-manager answers ACME DNS-01 challenges in the zone, and a Let's
    Encrypt issuer signs the console and balancerd certificates while the internal ones stay
    self-signed. The issuer starts on Let's Encrypt staging, as
    `<name_prefix>-letsencrypt-staging`; once staging has issued every certificate, set
    `acme_server_prod = true` and apply again.
  EOT
  type = object({
    zone_id     = string
    stem_domain = optional(string)
    subdomains  = optional(map(string), {})
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
