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
  description = "List of CIDR blocks allowed to reach the EKS cluster endpoint. Required (no default) so that an enterprise deployment makes an explicit choice instead of inheriting an open default. Pass ['0.0.0.0/0'] to allow all (lab use); production should pin a tight allowlist (e.g., ['203.0.113.0/24'])."
  type        = list(string)
  nullable    = false

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

# Ory variables
variable "ory_oel_registry" {
  description = "Base registry URL for Ory Enterprise License images. Defaults to the production Materialize-hosted registry proxy. Override for staging (ory.registry.staging.cloud.materialize.com/ory-artifacts) or a dev stack."
  type        = string
  default     = "ory.registry.cloud.materialize.com/ory-artifacts"
}

variable "ory_oel_image_tag" {
  description = "Image tag for OEL images."
  type        = string
  # renovate: datasource=docker depName=ory-artifacts/ory-enterprise/hydra-oel registryUrl=https://ory.registry.cloud.materialize.com
  default = "26.3.17"
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

variable "ory_kratos_cookie_domain" {
  description = "Domain Kratos scopes its session cookie to. It must cover both ory_kratos_fqdn and ory_ui_fqdn, and every host under it receives the session cookie, so pick the narrowest such domain, ideally one that holds only these hostnames. Example: mz.example.com for kratos.mz.example.com and auth.mz.example.com."
  type        = string
  nullable    = false
}

variable "enable_polis" {
  description = "Deploy Ory Polis (SAML-to-OIDC bridge) alongside Kratos and Hydra. When true, ory_polis_fqdn must be set and a dedicated RDS instance is provisioned for the polis database."
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
  description = "Extra CIDRs, besides Okta's SCIM egress ranges from okta-scim-source-ranges.json, allowed to reach the public Polis LoadBalancer. The browser reaches Polis directly for the SAML and OIDC hops, so set these to the public egress addresses your browsers appear as (VPN/NAT egress, office range). loadBalancerSourceRanges is a cloud firewall rule matched against the source IP as the cloud sees the packet, so a private VPC or tailnet CIDR (e.g. 100.64.0.0/10 or 10.x) will not match a browser coming over the internet and will lock those hops out. Combined with the Okta ranges and applied as loadBalancerSourceRanges. Leave empty to keep Polis unrestricted."
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

variable "upstream_identity_providers" {
  description = <<-EOT
    Upstream OIDC providers to expose as social sign-in methods on the Kratos selfservice UI. Each entry renders as a 'Sign in with X' button on the login page. Register the redirect URI https://<ory_kratos_fqdn>/self-service/methods/oidc/callback/<id> at the upstream IdP.

    Each provider only signs in emails under its allowed_email_domains (exact, lowercase domains; list subdomains separately). allowed_groups and group_prefix limit which of its groups reach Materialize. require_email_verified (default true) refuses emails the provider does not mark verified; Microsoft Entra ID does not send email_verified by default, so set it false there and rely on allowed_email_domains.
  EOT
  type = list(object({
    id                     = string
    provider               = optional(string, "generic")
    client_id              = string
    client_secret          = string
    issuer_url             = string
    scope                  = optional(list(string), ["openid", "email", "profile"])
    label                  = optional(string)
    allowed_email_domains  = list(string)
    allowed_groups         = optional(list(string))
    group_prefix           = optional(string)
    require_email_verified = optional(bool, true)
  }))
  default   = []
  nullable  = false
  sensitive = true
}

variable "saml_providers" {
  description = "SAML sign-in providers exposed via the Kratos SAML method, for Ory Polis (the jackson SAML-to-OIDC bridge). Each entry renders a 'Sign in with X' button whose SAML callback is https://<ory_kratos_fqdn>/self-service/methods/saml/callback/<id>. Leave as [] for none. allowed_email_domains, allowed_groups and group_prefix work as in upstream_identity_providers; require_email_verified defaults to false, since SAML assertions carry no email_verified claim."
  # raw_idp_metadata_xml is not set here: main.tf reads it from idp-metadata.xml
  # in this directory and injects it, so the large XML stays out of tfvars.
  type = list(object({
    id                     = string
    label                  = optional(string)
    client_id              = string
    client_secret          = string
    issuer_url             = string
    auth_url               = string
    token_url              = string
    allowed_email_domains  = list(string)
    allowed_groups         = optional(list(string))
    group_prefix           = optional(string)
    require_email_verified = optional(bool, false)
  }))
  default   = []
  nullable  = false
  sensitive = true
}

variable "materialize_version" {
  description = "Materialize release for both the operator Helm chart and environmentd, which must not drift. Null uses each module's default."
  type        = string
  default     = null
}

variable "balancerd_parameters" {
  description = "Dynamic configuration for balancerd, applied at runtime via a ConfigMap. Values are typed: numbers must be JSON numbers, e.g. { balancerd_max_connections = 5000 }. Null skips the ConfigMap."
  type        = any
  default     = null
}

variable "grafana_host" {
  description = "Hostname to expose Grafana on. Null keeps it on a ClusterIP Service, reachable only with `kubectl port-forward`. Exposure follows `internal_load_balancer` and `ingress_cidr_blocks`, the same as the Materialize load balancer. DNS for this name is yours to create."
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

variable "direct_oidc" {
  description = <<-EOT
    Point Materialize at an OIDC provider other than this example's Ory stack.

    Leave `null` to trust Hydra, which is the default. When set, these values become Materialize's
    issuer, audience and console client while the Ory stack keeps running alongside, which is how
    you move an existing deployment onto Ory without a sign-in outage. Clearing it is the cutover.

    `audience` is the list of accepted `aud` values, and `console_client_id` is the public client
    the console starts its authorization code flow with.
  EOT
  type = object({
    issuer               = string
    audience             = list(string)
    console_client_id    = string
    scopes               = optional(string, "openid email")
    authentication_claim = optional(string, "email")
  })
  default = null

  validation {
    condition     = var.direct_oidc == null || length(var.direct_oidc.audience) > 0
    error_message = "direct_oidc.audience must list at least one accepted audience; an empty list disables audience validation."
  }
}

variable "enable_ory_service_monitors" {
  description = <<-EOT
    Scrape Kratos's and Hydra's metrics into the monitoring stack. Ory serves them only on its
    unauthenticated admin listener, so the monitoring gateway scrapes a proxy in the Ory namespace
    that serves only the metrics path, and is never admitted to the admin API itself.
  EOT
  type        = bool
  default     = true
  nullable    = false
}
