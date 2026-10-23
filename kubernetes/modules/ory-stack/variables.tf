variable "namespace" {
  description = "Kubernetes namespace for the Ory components (Kratos, Hydra, selfservice UI)."
  type        = string
  default     = "ory"
  nullable    = false
}

variable "create_namespace" {
  description = "Whether the module should create the Ory namespace. Set to false if it already exists."
  type        = bool
  default     = true
  nullable    = false
}

# FQDNs -----------------------------------------------------------------------

variable "hydra_fqdn" {
  description = "Fully-qualified domain name for the Hydra OAuth2 public API (e.g. hydra.example.com). Used as the OIDC issuer URL."
  type        = string
  nullable    = false
}

variable "kratos_fqdn" {
  description = "Fully-qualified domain name for the Kratos public API (e.g. kratos.example.com). Used by the selfservice UI and as a browser redirect target."
  type        = string
  nullable    = false
}

variable "ui_fqdn" {
  description = "Fully-qualified domain name for the standalone Ory selfservice UI (e.g. id.example.com). Used for the UI's hostname and TLS certificate when deploy_selfservice_ui is true; unused (but still required) otherwise."
  type        = string
  nullable    = false
}

variable "deploy_selfservice_ui" {
  description = "Deploy the standalone Ory selfservice UI (login/consent/recovery pages) with its own LoadBalancer and TLS certificate. Set to false when another app (e.g. the Materialize console) hosts these pages, and set selfservice_ui_url to that app's URL."
  type        = bool
  default     = true
  nullable    = false
}

variable "selfservice_ui_url" {
  description = "External base URL that serves the Ory flow pages (login, consent, etc.) when deploy_selfservice_ui is false. Kratos and Hydra redirect the browser here. Ignored when deploy_selfservice_ui is true."
  type        = string
  default     = null
}

variable "polis_fqdn" {
  description = "Fully-qualified domain name for Polis (e.g. polis.example.com). Used as the NEXTAUTH_URL and the cert SAN; SAML and OAuth callbacks redirect through it. Required when enable_polis is true."
  type        = string
  default     = null
}

variable "polis_extra_dns_names" {
  description = "Extra SANs to add to the Polis TLS cert, e.g. a separate public SCIM hostname when the primary FQDN is served internally."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "kratos_cookie_domain" {
  description = "Domain Kratos scopes its session, CSRF and SSO continuity cookies to, e.g. auth.example.com. Required whenever a page that serves Kratos flows (the selfservice UI, or login_url in consent-only mode) is on a different host than Kratos, which with the selfservice UI on its own ui_fqdn is always. Every host under this domain receives the Kratos session cookie, so use the narrowest domain that covers Kratos (or the single-domain host) and those pages, ideally one that holds only the Ory hostnames. Null keeps the cookies host-only, which only works when those pages share Kratos's host."
  type        = string
  default     = null

  validation {
    condition = var.kratos_cookie_domain == null || (
      can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", coalesce(var.kratos_cookie_domain, "-"))) &&
      !can(regex("^[0-9.]+$", coalesce(var.kratos_cookie_domain, "-")))
    )
    error_message = "kratos_cookie_domain must be a lowercase domain with at least two labels, e.g. auth.example.com (no scheme, leading dot, port, path, wildcard or IP address)."
  }
}

variable "single_domain_fqdn" {
  description = "When set, Hydra and Kratos are served behind this single hostname under path prefixes (/hydra, /kratos) via a reverse proxy, instead of one hostname and LoadBalancer per service. The OIDC issuer becomes https://<fqdn>/hydra. Leave null to keep the per-service hostname layout. The selfservice UI keeps its own hostname because its assets are root-mounted, and Polis keeps its own hostname because the customer IdP must reach it directly."
  type        = string
  default     = null
}

variable "single_domain_proxy_image" {
  description = "Container image for the single-domain reverse proxy. Defaults to the public pingap image, pinned by digest. Point this at a hardened build pulled through the OEL registry proxy for production; the proxy pod uses the same OEL registry pull secret, so an image under the OEL proxy authenticates with the license key. The pod runs as UID 65532 with a read-only root filesystem and a writable /tmp."
  type        = string
  # renovate: datasource=docker depName=vicanso/pingap
  default  = "vicanso/pingap:0.12.1-full@sha256:88aaf15f953e64450162f19041952c65dfe43102d103d77198142b1a91ad7492"
  nullable = false
}

# Databases -------------------------------------------------------------------

variable "kratos_dsn" {
  description = "Postgres DSN for Kratos. Cloud-specific, computed by the caller from the database module outputs."
  type        = string
  sensitive   = true
  nullable    = false
}

variable "hydra_dsn" {
  description = "Postgres DSN for Hydra. Cloud-specific, computed by the caller from the database module outputs."
  type        = string
  sensitive   = true
  nullable    = false
}

variable "polis_dsn" {
  description = "Postgres DSN for Polis. Cloud-specific, computed by the caller from the database module outputs. Required when enable_polis is true."
  type        = string
  sensitive   = true
  default     = null
}

# OEL image pull --------------------------------------------------------------

variable "oel_registry" {
  description = "Base registry URL for Ory Enterprise License (OEL) images. Defaults to the production Materialize-hosted registry proxy (ory.registry.cloud.materialize.com/ory-artifacts). Override for staging (ory.registry.staging.cloud.materialize.com/ory-artifacts) or a dev stack. The Kratos and Hydra image repos are derived from this prefix."
  type        = string
  default     = "ory.registry.cloud.materialize.com/ory-artifacts"
  nullable    = false
}

variable "oel_image_tag" {
  description = "Tag for the OEL Kratos and Hydra images."
  type        = string
  nullable    = false
}

variable "license_key_jwt" {
  description = "Materialize license key JWT. Used as the password in the imagePullSecret to authenticate to the Ory registry proxy. The proxy validates the JWT signature, checks the ory entitlement, and forwards to Ory's Artifact Registry using Materialize's service account. Same JWT used by the materialize-instance module's license_key."
  type        = string
  sensitive   = true
  nullable    = false
}

variable "oel_registry_secret_name" {
  description = "Name of the imagePullSecrets Secret created in the Ory namespace."
  type        = string
  default     = "ory-oel-registry"
  nullable    = false
}

# TLS -------------------------------------------------------------------------

variable "cert_issuer_ref" {
  description = "cert-manager issuer reference used for the browser-facing TLS certificates. Object with 'name' and 'kind' (e.g. {name = '...', kind = 'ClusterIssuer'})."
  type = object({
    name = string
    kind = string
  })
  nullable = false
}

variable "cert_issuer_signs_cluster_local" {
  description = "Set to true when the issuer can sign single-label cluster.local SANs (typically the built-in self-signed ClusterIssuer). When true the cert SANs include the in-cluster service hostnames so in-cluster callers can hit the services directly; when false the SAN is dropped and in-cluster callers route via the external hostname (hairpin NAT through the LB)."
  type        = bool
  nullable    = false
}

# Materialize integration (optional) ------------------------------------------

variable "materialize_namespace" {
  description = "Namespace of the Materialize instance to wire up. When set, the module creates an OAuth2Client CRD in Hydra and admits that namespace to Hydra's public port (or the single-domain proxy). Set to null to deploy Ory without Materialize integration. The Materialize console HTTPS LoadBalancer itself is owned by the materialize-instance module."
  type        = string
  default     = null
}

variable "materialize_console_fqdn" {
  description = "Fully-qualified domain name the Materialize console will be served on (e.g. console.example.com). Required when materialize_namespace is set; used for the OAuth2 redirect URI and Hydra CORS."
  type        = string
  default     = null
}

variable "materialize_console_extra_fqdns" {
  description = "Additional FQDNs the Materialize console is served on (e.g. a VPN or tailnet hostname fronting the same pods). Each is registered alongside materialize_console_fqdn as an OAuth2 redirect URI, post-logout URI, and Hydra CORS origin, so sign-in completes from every origin."
  type        = list(string)
  default     = []
  nullable    = false
}

# Load balancer cloud-specific knobs ------------------------------------------

variable "lb_annotations" {
  description = "Annotations applied to all the public LoadBalancer Services (Hydra, Kratos, UI, and Polis when enabled). Use this to set cloud-specific LB knobs (Azure internal flag, GKE LB type, AWS LBC settings). Per-service values in lb_overrides are merged on top."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "lb_overrides" {
  description = "Per-service overrides for the LoadBalancer Services, keyed by service role: hydra, kratos, ui (the Ory selfservice UI, as in ui_fqdn and the lb_addresses output), polis, and single_domain (the single-domain reverse-proxy LB, used when single_domain_fqdn is set). annotations are merged over lb_annotations, with the override winning on key collisions; use this to mix internal and external LBs, e.g. internal Hydra/Kratos/selfservice UI with an internet-facing Polis for SCIM, or to restrict the single_domain proxy LB to a tailnet. source_ranges sets spec.loadBalancerSourceRanges, which the cloud controller enforces in the provider firewall; unlike lb_source_cidrs it restricts ingress even on clusters whose datapath does not enforce NetworkPolicy. load_balancer_ip sets spec.loadBalancerIP to a reserved static address, so a firewalled public LB (e.g. Polis) keeps a stable IP that peers can allowlist; null lets the cloud assign an ephemeral one."
  type = map(object({
    annotations      = optional(map(string), {})
    source_ranges    = optional(list(string))
    load_balancer_ip = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for key in keys(var.lb_overrides) : contains(["hydra", "kratos", "ui", "polis", "single_domain"], key)])
    error_message = "lb_overrides keys must be one of: hydra, kratos, ui, polis, single_domain."
  }
}

variable "lb_load_balancer_class" {
  description = "Value for spec.loadBalancerClass on the LoadBalancer Services. Leave null on Azure and GCP; set to 'service.k8s.aws/nlb' on AWS to route through the AWS Load Balancer Controller."
  type        = string
  default     = null
}

variable "lb_external_traffic_policy" {
  description = "Value for spec.externalTrafficPolicy on the LoadBalancer Services. Leave null to inherit the cluster default; set to 'Local' on AWS to preserve client source IPs through the NLB."
  type        = string
  default     = null
}

variable "lb_source_cidrs" {
  description = "CIDR blocks allowed to reach the Ory public listeners behind the load balancers (Hydra 4444 and Kratos 4433, or the single-domain proxy, plus the selfservice UI and Polis) via the NetworkPolicy, each on its own pods only. Defaults to all sources; tighten to your LB or office CIDR ranges to restrict ingress. NOTE: NetworkPolicy only takes effect on clusters whose datapath enforces it (GKE Dataplane V2, or a NetworkPolicy provider like Calico); on other clusters this input is silently ignored. For firewall-level enforcement that works everywhere, set source_ranges in lb_overrides instead."
  type        = list(string)
  default     = ["0.0.0.0/0"]
  nullable    = false
}

# Scheduling ------------------------------------------------------------------

variable "node_selector" {
  description = "Node selector applied to all Ory pods (Kratos, Hydra, selfservice UI)."
  type        = map(string)
  default     = {}
  nullable    = false
}

# Upstream identity providers -------------------------------------------------

variable "upstream_identity_providers" {
  description = <<-EOT
    Optional upstream identity providers exposed as social sign-in buttons on the selfservice UI. Most entries (Okta, Entra, Auth0, Google, etc.) use provider = "generic" and register their redirect URI at the upstream IdP as https://<kratos_fqdn>/self-service/methods/oidc/callback/<id>. Ory Polis goes in saml_providers instead.

    Each provider gets its own claim mapper (see the ory-kratos module):
    - allowed_email_domains (required): email domains this provider may sign in, matched exactly against the lowercased email (list subdomains separately).
    - allowed_groups / group_prefix: keep only these groups, or only groups starting with the prefix, from the provider's groups claim.
    - require_email_verified (default true): refuse emails the provider does not mark verified. Microsoft Entra ID does not send email_verified by default; set false there and rely on allowed_email_domains.
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
  description = "SAML sign-in providers exposed via the Kratos SAML method (selfservice.methods.saml), used for Ory Polis (the jackson SAML-to-OIDC bridge). Each entry renders as a 'Sign in with X' button whose SAML callback is https://<kratos_fqdn>/self-service/methods/saml/callback/<id>. Leave as [] when no SAML sign-in is configured. allowed_email_domains, allowed_groups and group_prefix work as in upstream_identity_providers; require_email_verified defaults to false, since SAML assertions carry no email_verified claim."
  type = list(object({
    id                     = string
    label                  = optional(string)
    client_id              = string
    client_secret          = string
    issuer_url             = string
    auth_url               = string
    token_url              = string
    raw_idp_metadata_xml   = string
    allowed_email_domains  = list(string)
    allowed_groups         = optional(list(string))
    group_prefix           = optional(string)
    require_email_verified = optional(bool, false)
  }))
  default   = []
  nullable  = false
  sensitive = true
}

# Escape hatches for chart overrides -----------------------------------------

variable "kratos_helm_values" {
  description = "Additional helm_values merged on top of the Kratos defaults. Use sparingly; the module already wires the values that the enterprise setup requires."
  type        = any
  default     = {}
}

variable "hydra_helm_values" {
  description = "Additional helm_values merged on top of the Hydra defaults. Use sparingly; the module already wires the values that the enterprise setup requires."
  type        = any
  default     = {}
}

variable "selfservice_ui_mode" {
  description = "How much of the selfservice UI to serve. \"full\" serves every Kratos self-service screen (login, registration, recovery, verification, settings, error) plus Hydra's consent screen. \"consent-only\" serves only the consent endpoint, the health endpoints and (when enabled) the token hook, leaving the user-facing flows to another app - typically the Materialize console; login_url is then required."
  type        = string
  default     = "full"
  nullable    = false

  validation {
    condition     = contains(["full", "consent-only"], var.selfservice_ui_mode)
    error_message = "selfservice_ui_mode must be one of: full, consent-only."
  }
}

variable "login_url" {
  description = "Full URL Hydra sends users to for login when the selfservice UI runs in consent-only mode, e.g. the Materialize console's https://console.example.com/account/login. Also becomes Kratos's login flow ui_url so Kratos redirects to the same page. Required when selfservice_ui_mode is \"consent-only\"; ignored otherwise (the UI's own /login is used)."
  type        = string
  default     = null

  validation {
    condition     = var.selfservice_ui_mode != "consent-only" || var.login_url != null
    error_message = "login_url must be set when selfservice_ui_mode is \"consent-only\": nothing else serves the login page in that mode."
  }
}

variable "selfservice_ui_token_hook_enabled" {
  description = "Serve Hydra's OAuth2 token hook from the selfservice UI and point Hydra at it. Hydra then calls the hook on every token issuance, so refresh tokens stop working for deactivated users and pick up groups refreshed at sign-in, instead of keeping what was granted at consent. Null (the default) turns it on whenever deploy_selfservice_ui is true. Hydra calls the UI's in-cluster service when cert_issuer_signs_cluster_local is true; otherwise the UI's cert only covers ui_fqdn, so Hydra calls https://<ui_fqdn> through the UI's load balancer, and token issuance fails unless that LB admits the cluster's own addresses (lb_overrides source_ranges) and Hydra trusts its CA."
  type        = bool
  default     = null
  nullable    = true

  validation {
    condition     = var.selfservice_ui_token_hook_enabled != true || var.deploy_selfservice_ui
    error_message = "selfservice_ui_token_hook_enabled requires deploy_selfservice_ui: the hook is served by the selfservice UI."
  }
}

variable "selfservice_ui_token_hook_max_auth_age_seconds" {
  description = "The token hook refuses user tokens once the user hasn't signed in through the IdP for this long. groups and email only change when the IdP mapper runs at sign-in, so this bounds how long a refresh-token chain can keep ones the IdP has since removed. 0 disables the check."
  type        = number
  default     = 604800
  nullable    = false

  validation {
    condition     = var.selfservice_ui_token_hook_max_auth_age_seconds >= 0
    error_message = "selfservice_ui_token_hook_max_auth_age_seconds must be 0 or more."
  }
}

variable "kratos_session_lifespan_seconds" {
  description = "How long a Kratos session lasts, in seconds. Hydra remembers a sign-in for as long, so this bounds how long a user removed at the IdP can keep authorizing new clients without going back to the IdP. Must not exceed selfservice_ui_token_hook_max_auth_age_seconds when that is above 0."
  type        = number
  default     = 28800
  nullable    = false

  validation {
    condition = var.kratos_session_lifespan_seconds >= 60 && (
      var.selfservice_ui_token_hook_max_auth_age_seconds == 0 ||
      var.kratos_session_lifespan_seconds <= var.selfservice_ui_token_hook_max_auth_age_seconds
    )
    error_message = "kratos_session_lifespan_seconds must be at least 60 and no more than selfservice_ui_token_hook_max_auth_age_seconds (when that is above 0)."
  }
}

variable "selfservice_ui_claim_metadata_public" {
  description = "Kratos metadata_public keys copied onto the issued tokens (both the id_token and the access token). The Kratos claim mapper writes the IdP's groups there, where users cannot change them. Materialize reads groups off the access token, so this pairs with Hydra's allowed_top_level_claims."
  type        = list(string)
  default     = ["groups"]
  nullable    = false
}

variable "selfservice_ui_claim_traits" {
  description = "Kratos identity trait names copied onto the issued tokens (both tokens). Empty by default: groups come from metadata_public, and a name may not appear in both lists."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = length(setintersection(var.selfservice_ui_claim_traits, var.selfservice_ui_claim_metadata_public)) == 0
    error_message = "A claim can't be in both selfservice_ui_claim_traits and selfservice_ui_claim_metadata_public: a user-editable trait would stand in for the IdP-sourced value."
  }
}

variable "kratos_recovery_enabled" {
  description = "Enable Kratos account recovery (selfservice.flows.recovery.enabled) and the matching link on the login screen. Off by default: identities come from the upstream IdP, which owns password resets."
  type        = bool
  default     = false
  nullable    = false
}

variable "kratos_verification_enabled" {
  description = "Enable Kratos address verification (selfservice.flows.verification.enabled) and the matching links on the screens. Off by default: addresses are asserted by the upstream IdP."
  type        = bool
  default     = false
  nullable    = false
}

variable "screens_registration_link_enabled" {
  description = "Whether the login screen links to registration. Kratos registration stays enabled for IdP just-in-time provisioning, but with password sign-up off the registration screen only repeats the SSO buttons, so the link is hidden by default."
  type        = bool
  default     = false
  nullable    = false
}

variable "dcr_audience_allowlist" {
  description = "Audience allow-list for OAuth2 clients that register themselves through dynamic client registration, such as MCP clients like Claude Code. A client asking for an RFC 8707 resource under one of these https URIs is granted that entry as its audience. Set it to the Materialize MCP resource URL(s), which must also be in Materialize's oidc_audience. Registration (POST /oauth2/register, enabled through hydra_helm_values) is unauthenticated and not rate limited by this module, so put a rate limit in front of Hydra's public endpoint if it is reachable from the internet."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "dcr_default_audience" {
  description = "Audience granted to self-registered OAuth2 clients that have none and requested no resource. Empty leaves those clients without an audience, so Materialize rejects their tokens."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "selfservice_ui_log_redact_pii" {
  description = "Redact personally identifiable information (email addresses, group names) from the selfservice UI's logs by hashing them. Set false temporarily while debugging sign-in issues."
  type        = bool
  default     = true
  nullable    = false
}

variable "selfservice_ui_extra_env" {
  description = "Additional environment variables passed to the selfservice UI container."
  type        = map(string)
  default     = {}
  nullable    = false
}

# OAuth2 client ---------------------------------------------------------------

variable "oauth2_client_name" {
  description = "Name of the Hydra OAuth2Client CRD registered for Materialize. Also the Secret name where Hydra Maester writes the credentials."
  type        = string
  default     = "materialize-oauth2-client"
  nullable    = false
}

variable "oauth2_client_audience" {
  description = "Audience value(s) the OAuth2 client embeds in issued JWTs. Materialize validates this against its OIDC_AUDIENCE setting."
  type        = list(string)
  default     = ["materialize"]
  nullable    = false
}

variable "oauth2_client_scope" {
  description = "OAuth2 scopes requested by the Materialize console during the authorization code flow."
  type        = string
  default     = "openid profile email offline"
  nullable    = false
}

variable "oauth2_client_post_logout_redirect_uris" {
  description = "URLs Hydra will accept as post_logout_redirect_uri when the Materialize console signs a user out. Null falls back to https://<materialize_console_fqdn>/ and https://<materialize_console_fqdn>/account/login, the path the console sends."
  type        = list(string)
  default     = null
}

# Polis (optional) ------------------------------------------------------------

variable "enable_polis" {
  description = "Deploy Ory Polis (SAML-to-OIDC bridge) as part of the stack. When true, polis_fqdn and polis_dsn must be provided."
  type        = bool
  default     = false
  nullable    = false
}

variable "polis_oel_image_tag" {
  description = "Tag for the Polis OEL image. Polis releases independently of Kratos/Hydra, so it has its own tag knob."
  type        = string
  # renovate: datasource=docker depName=ory-artifacts/ory-enterprise-polis/polis-oel registryUrl=https://ory.registry.cloud.materialize.com
  default  = "26.4.7"
  nullable = false
}

variable "polis_chart_version" {
  description = "Polis Helm chart version pulled from the OEL registry."
  type        = string
  # renovate: datasource=docker depName=ory-artifacts/helm-oel-polis/polis-oel registryUrl=https://ory.registry.cloud.materialize.com
  default  = "0.0.58"
  nullable = false
}

# Component secrets. Provide these (e.g. from a secret manager) to make the
# stack recoverable: they encrypt data at rest, so a database restore needs the
# exact same values. When left null, the sub-modules generate random secrets
# that live only in Terraform state.

variable "hydra_secrets_system" {
  description = "Hydra system secret. Encrypts data at rest in Hydra's database, including its signing keys. When null, a random secret is generated. Losing or rotating it makes the existing Hydra database unreadable."
  type        = string
  default     = null
  sensitive   = true
}

variable "hydra_secrets_cookie" {
  description = "Hydra cookie secret used to sign the login and consent session cookies. When null, a random secret is generated."
  type        = string
  default     = null
  sensitive   = true
}

variable "kratos_secrets_default" {
  description = "Kratos default secret used for signing and encryption. When null, a random secret is generated. Rotating invalidates existing sessions."
  type        = string
  default     = null
  sensitive   = true
}

variable "kratos_secrets_cookie" {
  description = "Kratos cookie secret used to sign session and CSRF cookies. When null, a random secret is generated."
  type        = string
  default     = null
  sensitive   = true
}

variable "kratos_secrets_cipher" {
  description = "Kratos cipher secret used to encrypt identity credentials and recovery data at rest. When null, a random 32-character secret is generated. Losing or rotating it makes the existing encrypted fields unreadable."
  type        = string
  default     = null
  sensitive   = true
}

variable "polis_admin_api_keys" {
  description = "Bearer token for Polis admin APIs. When null, the module generates a random 32-character key. Persist across applies, rotating invalidates admin-tool access."
  type        = string
  default     = null
  sensitive   = true
}

variable "polis_db_encryption_key" {
  description = "Symmetric key used by Polis to encrypt sensitive fields at rest in its database. When null, a random 32-character key is generated. WARNING: rotating invalidates existing encrypted records."
  type        = string
  default     = null
  sensitive   = true
}

variable "polis_nextauth_secret" {
  description = "Secret used by NextAuth.js for session signing in Polis. When null, a random 32-character secret is generated."
  type        = string
  default     = null
  sensitive   = true
}

variable "polis_helm_values" {
  description = "Additional helm_values merged on top of the Polis defaults."
  type        = any
  default     = {}
}

variable "polis_chart_registry" {
  description = "OCI registry host the Polis Helm chart is pulled from. Null falls back to the OEL registry proxy host (derived from oel_registry), which is the default and recommended path. Override if you want to bypass the proxy and pull the chart directly from a different OCI registry."
  type        = string
  default     = null
}

variable "polis_chart_repository" {
  description = "OCI repository path for the Polis Helm chart (no leading slash, no registry host). Null falls back to the proxy-aware path derived from oel_registry. Override when the chart lives outside the proxy path, e.g. 'ory-artifacts/helm-oel-polis/polis-oel' on GCP Artifact Registry."
  type        = string
  default     = null
}

variable "polis_chart_oci_username" {
  description = "Username for authenticating to the Polis chart OCI registry. Defaults to 'jwt' (proxy path); use '_json_key' when pulling directly from GCP Artifact Registry."
  type        = string
  default     = "jwt"
  nullable    = false
}

variable "polis_chart_oci_password" {
  description = "Password for authenticating to the Polis chart OCI registry. Null falls back to license_key_jwt (proxy path). Set to the contents of a GCP service-account JSON key when pulling the chart directly from GCP Artifact Registry."
  type        = string
  default     = null
  sensitive   = true
}

variable "enable_service_monitors" {
  description = "Create ServiceMonitors for Kratos and Hydra. Ory serves metrics only on its unauthenticated admin listener, so the scraper never reaches it: it scrapes a small nginx proxy in the Ory namespace that serves only `GET /admin/metrics/prometheus` from each Kratos and Hydra pod. The prometheus-operator CRDs must be installed before this module, or the charts leave the monitors out."
  type        = bool
  default     = false
  nullable    = false
}

variable "monitoring_namespace" {
  description = "Namespace the metrics scraper runs in, admitted to the metrics proxy when `enable_service_monitors` is set."
  type        = string
  default     = "monitoring"
  nullable    = false
}

variable "metrics_scraper_pod_labels" {
  description = "Labels of the pods in `monitoring_namespace` admitted to the metrics proxy when `enable_service_monitors` is set. The default matches the materialize-monitoring gateway, which is what scrapes ServiceMonitors."
  type        = map(string)
  default     = { "app.kubernetes.io/name" = "alloy-gateway" }
  nullable    = false
}

variable "metrics_proxy_image" {
  description = "Container image for the metrics proxy deployed when `enable_service_monitors` is set. Must be an nginx-unprivileged build: the pod runs as UID 101 with a read-only root filesystem. Pinned by digest by default."
  type        = string
  # renovate: datasource=docker depName=nginxinc/nginx-unprivileged
  default  = "docker.io/nginxinc/nginx-unprivileged:1.30.6-alpine@sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03"
  nullable = false
}
