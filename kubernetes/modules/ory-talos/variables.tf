variable "namespace" {
  description = "Kubernetes namespace for Ory Talos."
  type        = string
  default     = "ory-talos"
  nullable    = false
}

variable "create_namespace" {
  description = "Whether to create the Kubernetes namespace. Set to false if the namespace already exists."
  type        = bool
  default     = true
  nullable    = false
}

variable "name" {
  description = "Name prefix for Talos Kubernetes resources."
  type        = string
  default     = "talos"
  nullable    = false
}

variable "dsn" {
  description = "PostgreSQL DSN for Talos. Maps to the TALOS_DB_DSN env var. Example: postgres://user:password@host:5432/talos?sslmode=require"
  type        = string
  sensitive   = true
  nullable    = false
}

variable "credentials_issuer" {
  description = "Issuer claim Talos puts in derived JWTs. Maps to TALOS_CREDENTIALS_ISSUER. Must match what downstream services (e.g., Materialize) validate as the OIDC issuer. Example: https://talos.internal.example.com"
  type        = string
  nullable    = false
}

# Required secrets (each must be >= 32 characters per Talos config schema)
variable "default_secret" {
  description = "Secret used by Talos default components, set as TALOS_SECRETS_DEFAULT_CURRENT. Must be at least 32 characters. If null, a random 32-character secret is generated."
  type        = string
  default     = null
  sensitive   = true
}

variable "hmac_secret" {
  description = "HMAC secret used by Talos for API key generation, set as TALOS_SECRETS_HMAC_CURRENT. Must be at least 32 characters. If null, a random 32-character secret is generated."
  type        = string
  default     = null
  sensitive   = true
}

variable "pagination_secret" {
  description = "Secret used for signing pagination tokens, set as TALOS_SECRETS_PAGINATION_CURRENT. Must be at least 32 characters. If null, a random 32-character secret is generated."
  type        = string
  default     = null
  sensitive   = true
}

# Image
variable "image_registry" {
  description = "Docker image registry for the Talos OEL container. Mirrors the registry layout used by other Ory OEL components."
  type        = string
  default     = "europe-docker.pkg.dev"
  nullable    = false
}

variable "image_repository" {
  description = "Docker image repository for the Talos OEL container. Default follows the Ory enterprise naming convention; override for mirrored / air-gapped registries."
  type        = string
  default     = "ory-artifacts/ory-enterprise-talos/talos-oel"
  nullable    = false
}

variable "image_tag" {
  description = "Docker image tag for the Talos OEL container. Pin a specific version in production; 'latest' is the default for early-access exploration."
  type        = string
  default     = "latest"
  nullable    = false
}

variable "image_pull_secrets" {
  description = "List of Kubernetes secret names (in the Talos namespace) used to pull the OEL image. During early access, the Talos image is gated by a separate service-account key from the rest of OEL; pass the secret name backing that key here."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "image_pull_policy" {
  description = "Image pull policy for Talos pods."
  type        = string
  default     = "IfNotPresent"
  nullable    = false
}

# Service
variable "http_port" {
  description = "Port that Talos's HTTP API listens on (TALOS_SERVE_HTTP_PORT). Default matches the Talos config schema."
  type        = number
  default     = 4420
  nullable    = false
}

variable "metrics_port" {
  description = "Port that Talos's metrics endpoint listens on (TALOS_SERVE_METRICS_PORT). Commercial feature; defaults to 4422 to match Talos's default."
  type        = number
  default     = 4422
  nullable    = false
}

# Deployment
variable "replica_count" {
  description = "Number of Talos replicas."
  type        = number
  default     = 2
  nullable    = false
}

variable "resources" {
  description = "Resource requests and limits for Talos pods."
  type = object({
    requests = optional(object({
      cpu    = optional(string, "100m")
      memory = optional(string, "256Mi")
    }))
    limits = optional(object({
      cpu    = optional(string)
      memory = optional(string, "256Mi")
    }))
  })
  default = {
    requests = {}
    limits   = {}
  }
  nullable = false
}

variable "node_selector" {
  description = "Node selector for Talos pods."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "tolerations" {
  description = "Tolerations for Talos pods."
  type = list(object({
    key      = string
    value    = optional(string)
    operator = optional(string, "Equal")
    effect   = string
  }))
  default  = []
  nullable = false
}

# Behavior knobs
variable "log_level" {
  description = "TALOS_LOG_LEVEL. One of debug, info, warn, error."
  type        = string
  default     = "info"
  nullable    = false
  validation {
    condition     = contains(["debug", "info", "warn", "error"], var.log_level)
    error_message = "log_level must be one of: debug, info, warn, error."
  }
}

variable "log_format" {
  description = "TALOS_LOG_FORMAT. One of json or text."
  type        = string
  default     = "json"
  nullable    = false
  validation {
    condition     = contains(["json", "text"], var.log_format)
    error_message = "log_format must be one of: json, text."
  }
}

variable "extra_env" {
  description = "Additional environment variables for Talos as a map of name to value. Useful for any TALOS_* config not yet wired through a dedicated variable (e.g., cache, rate-limit, tracing, all of which are commercial features in Talos)."
  type        = map(string)
  default     = {}
  nullable    = false
}
