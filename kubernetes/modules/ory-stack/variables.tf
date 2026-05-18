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

# Hostnames -------------------------------------------------------------------

variable "hydra_hostname" {
  description = "External hostname for the Hydra OAuth2 public API. Used as the OIDC issuer URL."
  type        = string
  nullable    = false
}

variable "kratos_hostname" {
  description = "External hostname for the Kratos public API. Used by the selfservice UI and as a browser redirect target."
  type        = string
  nullable    = false
}

variable "ui_hostname" {
  description = "External hostname for the Ory selfservice UI."
  type        = string
  nullable    = false
}

variable "cookie_parent_domain" {
  description = "Parent domain used as the cookie domain for Kratos session and CSRF cookies so they apply across sibling subdomains. Defaults to the parent domain of kratos_hostname (e.g. kratos.example.com -> example.com)."
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
  description = "Base registry URL for Ory Enterprise License (OEL) images. Example: europe-docker.pkg.dev/ory-artifacts. The Kratos and Hydra image repos are derived from this prefix."
  type        = string
  nullable    = false
}

variable "oel_image_tag" {
  description = "Tag for the OEL Kratos and Hydra images."
  type        = string
  nullable    = false
}

variable "oel_key_file" {
  description = "Path to the GCP service account JSON key file used to pull OEL images. SECURITY: the key contents are embedded in Terraform state in plaintext; treat state as sensitive."
  type        = string
  nullable    = false
}

variable "oel_registry_host" {
  description = "Hostname (no path) of the OEL container registry. Used as the dockerconfigjson auths key."
  type        = string
  default     = "europe-docker.pkg.dev"
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

variable "materialize_console_hostname" {
  description = "External hostname the Materialize console will be served on. Required when materialize_namespace is set; used for the OAuth2 redirect URI and Hydra CORS."
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

# Scheduling ------------------------------------------------------------------

variable "node_selector" {
  description = "Node selector applied to all Ory pods (Kratos, Hydra, selfservice UI)."
  type        = map(string)
  default     = {}
  nullable    = false
}

# Upstream identity providers -------------------------------------------------

variable "upstream_oidc_providers" {
  description = "Optional upstream OIDC providers (Okta, Entra, Auth0, Google, etc.) exposed as social sign-in buttons on the selfservice UI. Each entry's redirect URI is registered at the upstream IdP as https://<kratos_hostname>/self-service/methods/oidc/callback/<id>."
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
