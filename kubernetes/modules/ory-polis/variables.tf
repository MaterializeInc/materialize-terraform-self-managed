variable "namespace" {
  description = "Kubernetes namespace for Ory Polis."
  type        = string
  default     = "ory-polis"
  nullable    = false
}

variable "create_namespace" {
  description = "Whether to create the Kubernetes namespace. Set to false if the namespace already exists."
  type        = bool
  default     = true
  nullable    = false
}

variable "release_name" {
  description = "Helm release name. Also used as the resource name prefix inside the chart. Defaulting to 'polis' produces simple resource names like 'polis' / 'polis-migration' because the chart's fullname helper collapses '<release>-<chart>' when one contains the other."
  type        = string
  default     = "polis"
  nullable    = false
}

variable "dsn" {
  description = "PostgreSQL DSN for Polis. Injected as the DB_URL env var via a Kubernetes Secret (the chart's built-in secret hardcodes a CockroachDB DSN, so this module always ships its own). Example: postgres://user:password@host:5432/polis?sslmode=require"
  type        = string
  sensitive   = true
  nullable    = false
}

# Helm chart source
variable "chart_registry" {
  description = "OCI registry hostname for the Polis Helm chart."
  type        = string
  default     = "europe-docker.pkg.dev"
  nullable    = false
}

variable "chart_repository" {
  description = "OCI repository path for the Polis Helm chart (relative to chart_registry)."
  type        = string
  default     = "ory-artifacts/helm-oel-polis/polis-oel"
  nullable    = false
}

variable "chart_version" {
  description = "Polis Helm chart version. See the Ory Polis release notes for the version that pairs with your OEL image tag."
  type        = string
  default     = "0.0.20"
  nullable    = false
}

variable "oci_registry_username" {
  description = "Username for authenticating to the Polis Helm OCI registry. For GCP Artifact Registry (the default chart_registry), use '_json_key'. Ignored when oci_registry_password is null."
  type        = string
  default     = "_json_key"
  nullable    = false
}

variable "oci_registry_password" {
  description = "Password / token for authenticating to the Polis Helm OCI registry. For GCP Artifact Registry, pass the full contents of a service-account JSON key via file('path/to/key.json'). When null, no authentication is configured (only viable for an anonymous registry)."
  type        = string
  default     = null
  sensitive   = true
}

variable "install_timeout" {
  description = "Helm install/upgrade timeout in seconds."
  type        = number
  default     = 600
  nullable    = false
}

# Application configuration
variable "external_url" {
  description = "Externally-reachable HTTPS URL for Polis. Used as the NEXTAUTH_URL so OIDC and SAML flows redirect through it. Polis does not terminate TLS itself, so HTTPS must be provided by an ingress or LoadBalancer in front of the pod. Example: https://polis.internal.example.com"
  type        = string
  nullable    = false
}

variable "admin_api_keys" {
  description = "Bearer token for authenticating requests to Polis admin APIs (set as the API_KEYS env var inside the Polis container). If null, a random 32-character key is generated."
  type        = string
  default     = null
  sensitive   = true
}

variable "nextauth_secret" {
  description = "Secret used by NextAuth.js for session signing. If null, a random 32-character secret is generated."
  type        = string
  default     = null
  sensitive   = true
}

variable "db_encryption_key" {
  description = "Symmetric key used by Polis to encrypt sensitive fields (e.g. IdP credentials) before storing them in the database. Required by the chart. If null, a random 32-character key is generated. WARNING: rotating this key invalidates all existing encrypted records, so persist it across applies (e.g., via Terraform state or a Vault lookup)."
  type        = string
  default     = null
  sensitive   = true
}

variable "db_ssl" {
  description = "Whether Polis should connect to its database over TLS. Maps to the chart's dbSSL value and the DB_SSL env var."
  type        = bool
  default     = true
  nullable    = false
}

variable "hosted" {
  description = "When true, Polis runs in 'hosted' mode and exposes the multi-tenant admin UI. Leave false for an embedded single-tenant deployment fronting a single Materialize console."
  type        = bool
  default     = false
  nullable    = false
}

variable "idp_enabled" {
  description = "Enable Polis's IdP routes (SAML/OAuth ACS, /.well-known/, etc.). Required when Polis is acting as an IdP for downstream consumers like Kratos."
  type        = bool
  default     = true
  nullable    = false
}

variable "nextauth_acl" {
  description = "Optional NextAuth ACL string. Restricts which email addresses can authenticate to the Polis admin UI. Empty allows all."
  type        = string
  default     = ""
  nullable    = false
}

variable "saml_audience" {
  description = "Optional SAML audience identifier (Polis's SAML entity ID). When set, injected as the SAML_AUDIENCE env var on the Polis container. Must match the audience configured on the upstream IdP. Leave null to inherit Polis's built-in default."
  type        = string
  default     = null
}

# Image
variable "image_registry" {
  description = "Override for the Polis container image registry. Null uses the chart's default (europe-docker.pkg.dev for OEL)."
  type        = string
  default     = null
}

variable "image_repository" {
  description = "Override for the Polis container image repository. Null uses the chart's default (ory-artifacts/ory-enterprise-polis/polis-oel)."
  type        = string
  default     = null
}

variable "image_tag" {
  description = "Override for the Polis container image tag. Null uses the chart's default (typically pinned to the chart's AppVersion)."
  type        = string
  default     = null
}

variable "image_pull_policy" {
  description = "Image pull policy for Polis pods."
  type        = string
  default     = "IfNotPresent"
  nullable    = false
}

variable "image_pull_secrets" {
  description = "List of Kubernetes secret names (in the Polis namespace) used to pull the OEL image."
  type        = list(string)
  default     = []
  nullable    = false
}

# Service
variable "port" {
  description = "Cluster-IP service port for Polis. The container always listens on 5225; this is just the front-side port the service publishes."
  type        = number
  default     = 5225
  nullable    = false
}

# Deployment
variable "replica_count" {
  description = "Number of Polis replicas."
  type        = number
  default     = 2
  nullable    = false
}

variable "resources" {
  description = "Resource requests and limits for Polis pods."
  type = object({
    requests = optional(object({
      cpu    = optional(string, "250m")
      memory = optional(string, "512Mi")
    }))
    limits = optional(object({
      cpu    = optional(string)
      memory = optional(string, "512Mi")
    }))
  })
  default = {
    requests = {}
    limits   = {}
  }
  nullable = false
}

variable "node_selector" {
  description = "Node selector for Polis pods."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "tolerations" {
  description = "Tolerations for Polis pods."
  type = list(object({
    key      = string
    value    = optional(string)
    operator = optional(string, "Equal")
    effect   = string
  }))
  default  = []
  nullable = false
}

variable "extra_env" {
  description = "Additional environment variables for the Polis container as a map of name to value. Wired through the chart's deployment.extraEnvs list."
  type        = map(string)
  default     = {}
  nullable    = false
}

# Observability
variable "monitoring_enabled" {
  description = "When false, the chart's default OTLP endpoints (which point at a kube-prometheus-stack installation in 'observability') are blanked out so Polis doesn't keep trying to reach a non-existent collector. Set to true and override via helm_values when you have one."
  type        = bool
  default     = false
  nullable    = false
}

# Escape hatch
variable "helm_values" {
  description = "Additional values to merge into the Helm release. Deep-merged on top of this module's defaults so individual keys can be overridden without rewriting whole blocks."
  type        = any
  default     = {}
}
