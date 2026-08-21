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
  description = "Materialize license key JWT. Required for this example: used both by Materialize itself and as the password in the imagePullSecret that authenticates to the Materialize-hosted Ory registry proxy."
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
  description = "List of CIDR blocks (with display names) allowed to reach the GKE master endpoint. Required (no default) so that an enterprise deployment makes an explicit choice instead of inheriting an open default. Pass a single 0.0.0.0/0 entry to allow all (lab use); production should pin a tight allowlist."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
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

# Node pool sizing. Defaults are production-ish; override in tfvars for cheaper
# multi-day testing (e.g. c4a-highmem-4-lssd / c4-standard-4, min_nodes = 1).

variable "generic_nodepool" {
  description = "Generic Kubernetes node pool: hosts everything except the Materialize instance pods (operator, Ory, cert-manager, prometheus, grafana)."
  type = object({
    machine_type = optional(string, "c4-standard-8")
    disk_type    = optional(string, "hyperdisk-balanced")
    disk_size_gb = optional(number, 50)
    min_nodes    = optional(number, 2)
    max_nodes    = optional(number, 5)
  })
  default  = {}
  nullable = false
}

variable "materialize_nodepool" {
  description = "Materialize-dedicated Kubernetes node pool: hosts environmentd, clusterd, balancerd, console. Tainted so only Materialize pods schedule here. Local SSD provides swap. C4A only offers local SSDs on -lssd machine variants with a fixed disk count that local_ssd_count must match (c4a-highmem-8-lssd bundles 2). To disable swap, use a non-lssd machine type and set local_ssd_count = 0 and swap_enabled = false (uses more memory but cheaper)."
  type = object({
    machine_type    = optional(string, "c4a-highmem-8-lssd")
    disk_type       = optional(string, "hyperdisk-balanced")
    disk_size_gb    = optional(number, 100)
    min_nodes       = optional(number, 2)
    max_nodes       = optional(number, 5)
    local_ssd_count = optional(number, 2)
    swap_enabled    = optional(bool, true)
  })
  default  = {}
  nullable = false
}

# Ory variables
variable "ory_oel_registry" {
  description = "Base registry URL for Ory Enterprise License images. Defaults to the production Materialize-hosted registry proxy. Override for staging (ory.registry.staging.cloud.materialize.com/ory-artifacts) or a dev stack."
  type        = string
  default     = "ory.registry.cloud.materialize.com/ory-artifacts"
}

variable "ory_oel_image_tag" {
  description = "Image tag for OEL images."
  type        = string
  default     = "26.2.22"
}

variable "ory_hydra_fqdn" {
  description = "External hostname for the Hydra OAuth2 public API. Used as the OIDC issuer URL. Example: hydra.internal.example.com"
  type        = string
}

variable "ory_ui_fqdn" {
  description = "External hostname for the Ory selfservice UI (login/consent pages). Example: auth.internal.example.com"
  type        = string
}

variable "ory_kratos_fqdn" {
  description = "External hostname for the Kratos public API. Kratos flows return browser-facing URLs using this hostname. Example: kratos.internal.example.com"
  type        = string
}

variable "enable_polis" {
  description = "Deploy Ory Polis (SAML-to-OIDC bridge) alongside Kratos and Hydra. When true, ory_polis_fqdn must be set and a polis database is provisioned on the Ory Cloud SQL instance."
  type        = bool
  default     = false
  nullable    = false
}

variable "ory_polis_fqdn" {
  description = "External hostname for Ory Polis (SAML-to-OIDC bridge). Used as the NEXTAUTH_URL so SAML and OAuth callbacks redirect through it. Required when enable_polis is true. Example: polis.internal.example.com"
  type        = string
  default     = null
}

variable "polis_helm_values" {
  description = "Additional Helm values deep-merged into the Polis chart. Escape hatch for overriding resources, node selectors, tolerations, etc."
  type        = any
  default     = {}
}

variable "ory_polis_source_ranges" {
  description = "Extra CIDRs, besides Okta's SCIM egress ranges from okta-scim-source-ranges.json, allowed to reach the Polis LoadBalancer. Set these to your VPC / VPN / tailnet ranges so the browser SAML and OIDC hops still work, since the browser reaches Polis directly. Combined with the Okta ranges and applied as loadBalancerSourceRanges. Leave empty to keep Polis unrestricted. Only lock Polis down when browser access to Ory is internal; a fully public browser flow needs Polis reachable from anywhere."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "materialize_console_fqdn" {
  description = "External hostname for the Materialize console. Used to construct the OAuth2 redirect URI. Example: materialize.internal.example.com"
  type        = string
}

variable "materialize_balancerd_fqdn" {
  description = "External hostname for balancerd (the SQL-over-HTTP endpoint). The Materialize console's browser-side JS calls balancerd directly, so an externally-accessed console needs balancerd reachable too. Point an A record at the balancerd LB IP after apply. Example: balancerd.internal.example.com"
  type        = string
}

variable "cert_issuer_ref" {
  description = "Bring-your-own cert-manager (Cluster)Issuer used to sign the browser-facing TLS certs (Materialize console / balancerd, Hydra, Kratos, selfservice UI). When null, the example falls back to the built-in self-signed issuer for browser-facing certs (the demo path). The internal mTLS cert (with *.cluster.local SANs) always uses the self-signed cluster issuer because public ACME issuers like Let's Encrypt cannot sign cluster.local. See the README for an example of plugging in a Let's Encrypt + Cloudflare DNS-01 issuer."
  type = object({
    name = string
    kind = string
  })
  default = null
}

variable "upstream_oidc_providers" {
  description = "Upstream OIDC providers to expose as social sign-in methods on the Kratos selfservice UI. Each entry renders as a 'Sign in with X' button on the login page. Leave as [] for password-only login. Register the redirect URI https://<ory_kratos_fqdn>/self-service/methods/oidc/callback/<id> at the upstream IdP."
  type = list(object({
    id            = string
    provider      = optional(string, "generic")
    client_id     = string
    client_secret = string
    issuer_url    = string
    scope         = optional(list(string), ["openid", "email", "profile"])
    label         = optional(string)
  }))
  default   = []
  nullable  = false
  sensitive = true
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
  description = "Optional hostname to reach Grafana on. The load balancer is created regardless and answers on an IP; setting this configures Grafana's `root_url` for share links, alert notifications, and OAuth redirects. DNS for this name is yours to create."
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
