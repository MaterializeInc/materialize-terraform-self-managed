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
  description = "Fully-qualified domain name for the Ory selfservice UI (e.g. id.example.com)."
  type        = string
  nullable    = false
}

variable "cookie_parent_domain" {
  description = "Parent domain used as the cookie domain for Kratos session and CSRF cookies so they apply across sibling subdomains. Defaults to the parent domain of kratos_fqdn (e.g. kratos.example.com -> example.com). Falls back to kratos_fqdn itself when it has no '.' separator."
  type        = string
  default     = null
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

variable "oel_registry_host" {
  description = "Hostname (no path) of the OEL container registry. Used as the dockerconfigjson auths key. Defaults to the production proxy host."
  type        = string
  default     = "ory.registry.cloud.materialize.com"
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
  description = "Namespace of the Materialize instance to wire up. When set, the module creates an OAuth2Client CRD in Hydra, NetworkPolicies bridging the two namespaces, and the console HTTPS LoadBalancer. Set to null to deploy Ory without Materialize integration."
  type        = string
  default     = null
}

variable "materialize_instance_name" {
  description = "Name of the Materialize instance. Required when materialize_namespace is set; used for the console HTTPS Service selector and name prefix."
  type        = string
  default     = null
}

variable "materialize_instance_resource_id" {
  description = "resource_id from the Materialize instance status. Required when materialize_namespace is set; used for the console HTTPS Service selector."
  type        = string
  default     = null
}

variable "materialize_console_fqdn" {
  description = "Fully-qualified domain name the Materialize console will be served on (e.g. console.example.com). Required when materialize_namespace is set; used for the OAuth2 redirect URI and Hydra CORS."
  type        = string
  default     = null
}

# Load balancer cloud-specific knobs ------------------------------------------

variable "lb_annotations" {
  description = "Annotations applied to the public LoadBalancer Services (Hydra, Kratos, UI, and the Materialize console). Use this to set cloud-specific LB knobs (Azure internal flag, GKE LB type, AWS LBC settings)."
  type        = map(string)
  default     = {}
  nullable    = false
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
  description = "CIDR blocks allowed to reach the Ory public ports (Hydra 4444, Kratos 4433, selfservice UI 3000) via the NetworkPolicy. Defaults to all sources; tighten to your LB or office CIDR ranges to restrict ingress."
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

variable "upstream_oidc_providers" {
  description = "Optional upstream OIDC providers (Okta, Entra, Auth0, Google, etc.) exposed as social sign-in buttons on the selfservice UI. Each entry's redirect URI is registered at the upstream IdP as https://<kratos_fqdn>/self-service/methods/oidc/callback/<id>."
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
