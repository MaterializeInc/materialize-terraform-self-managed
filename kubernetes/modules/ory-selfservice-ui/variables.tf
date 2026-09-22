variable "namespace" {
  description = "Kubernetes namespace for the Ory selfservice UI."
  type        = string
  default     = "ory"
  nullable    = false
}

variable "create_namespace" {
  description = "Whether to create the Kubernetes namespace."
  type        = bool
  default     = false
  nullable    = false
}

variable "name" {
  description = "Name for the selfservice UI Kubernetes resources."
  type        = string
  default     = "ory-selfservice-ui"
  nullable    = false
}

variable "image_repository" {
  description = "Docker image repository for the selfservice UI. Defaults to Materialize's own ory-selfservice service (https://github.com/MaterializeInc/ory-selfservice), published to GHCR today and to Docker Hub as materialize/ory-selfservice once it is public. Air-gapped installs mirror the image into their own registry and point this at the mirror."
  type        = string
  default     = "ghcr.io/materializeinc/ory-selfservice"
  nullable    = false
}

variable "image_tag" {
  description = "Docker image tag for the selfservice UI. Tracks ory-selfservice releases; pin it (rather than following a floating tag) so upgrades are deliberate, and mirror the same tag for air-gapped installs."
  type        = string
  default     = "v0.1.0"
  nullable    = false
}

variable "image_pull_policy" {
  description = "Image pull policy."
  type        = string
  default     = "IfNotPresent"
  nullable    = false
}

variable "port" {
  description = "Port the selfservice UI listens on."
  type        = number
  default     = 3000
  nullable    = false
}

variable "kratos_public_url" {
  description = "Internal URL for the Kratos public API. Example: http://kratos-public.ory.svc.cluster.local:4433. Required when screens_enabled is true; consent-only deployments (screens_enabled = false) never talk to the Kratos public API and can leave it null."
  type        = string
  default     = null
}

variable "kratos_admin_url" {
  description = "Internal URL for the Kratos admin API. Example: http://kratos-admin.ory.svc.cluster.local:4434"
  type        = string
  nullable    = false
}

variable "kratos_browser_url" {
  description = "Browser-accessible URL for the Kratos public API. If not set, kratos_public_url is used. Unused when screens_enabled is false, since the browser never reaches the self-service screens."
  type        = string
  default     = null
}

variable "hydra_admin_url" {
  description = "Internal URL for the Hydra admin API. Example: http://hydra-admin.ory.svc.cluster.local:4445"
  type        = string
  nullable    = false
}

variable "cookie_secret" {
  description = "Secret for signing cookies. Must be at least 32 characters. If not set, a random 32-character secret will be generated."
  type        = string
  default     = null
  sensitive   = true
}

variable "csrf_cookie_secret" {
  description = "Secret for CSRF cookie hashing. Must be at least 32 characters. If not set, a random 32-character secret will be generated."
  type        = string
  default     = null
  sensitive   = true
}

variable "csrf_cookie_name" {
  description = "Name of the CSRF cookie. Should be prefixed with __HOST- in production."
  type        = string
  default     = "__HOST-ory-ui-x-csrf-token"
  nullable    = false
}

variable "disable_secure_csrf_cookies" {
  description = "Disable secure CSRF cookies. Only use in local development without HTTPS."
  type        = bool
  default     = false
  nullable    = false
}

variable "tls_cert_secret_name" {
  description = "Name of a Kubernetes TLS secret (containing tls.crt and tls.key) to mount into the pod and serve HTTPS from. Typically created by cert-manager. When set, the selfservice UI serves HTTPS directly."
  type        = string
  default     = null
}

variable "trust_mounted_ca_cert" {
  description = "When true and tls_cert_secret_name is set, point NODE_EXTRA_CA_CERTS at the ca.crt key of the mounted TLS secret so the UI's outbound HTTPS calls (to Kratos/Hydra) trust the issuing CA. Only useful when those upstreams are served by the same in-cluster CA (e.g., cert-manager's self-signed ClusterIssuer). Leave false when the upstream certs are signed by a public CA (Let's Encrypt, corporate trust bundle) that Node.js already trusts, since the mounted secret may not even contain a ca.crt key."
  type        = bool
  default     = false
  nullable    = false
}

variable "trusted_client_ids" {
  description = "List of OAuth2 client IDs that are trusted and can skip the consent screen."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "project_name" {
  description = "Project name displayed in the UI."
  type        = string
  default     = "Materialize"
  nullable    = false
}

variable "replica_count" {
  description = "Number of replicas."
  type        = number
  default     = 2
  nullable    = false
}

variable "resources" {
  description = "Resource requests and limits for selfservice UI pods."
  type = object({
    requests = optional(object({
      cpu    = optional(string, "100m")
      memory = optional(string, "128Mi")
    }))
    limits = optional(object({
      cpu    = optional(string)
      memory = optional(string, "128Mi")
    }))
  })
  default = {
    requests = {}
    limits   = {}
  }
  nullable = false
}

variable "node_selector" {
  description = "Node selector for selfservice UI pods."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "tolerations" {
  description = "Tolerations for selfservice UI pods."
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
  description = "Additional environment variables as a map of name to value."
  type        = map(string)
  default     = {}
  nullable    = false
}

# ory-selfservice behaviour -----------------------------------------------------

variable "screens_enabled" {
  description = "Serve the Kratos self-service screens (login, registration, recovery, verification, settings, error). Set to false for consent-only mode, where the service only serves Hydra's consent endpoint, the health endpoints and (when enabled) the token hook, and another app - typically the Materialize console - owns the user-facing flows. In that mode kratos_public_url and kratos_browser_url are unused."
  type        = bool
  default     = true
  nullable    = false
}

variable "claim_traits_id_token" {
  description = "Identity trait names copied from the Kratos identity onto every id_token issued through the consent flow. Pairs with Hydra's allowed_top_level_claims so the claims land top-level rather than under Hydra's ext."
  type        = list(string)
  default     = ["groups"]
  nullable    = false
}

variable "claim_traits_access_token" {
  description = "Identity trait names copied from the Kratos identity onto every access token issued through the consent flow. Materialize reads groups off the access token, which is what makes MCP OAuth work."
  type        = list(string)
  default     = ["groups"]
  nullable    = false
}

variable "token_hook_enabled" {
  description = "Serve POST /hooks/token, Hydra's token hook. Hydra calls it on every token issuance so claims can be refreshed from Kratos on refresh-token grants, not just at consent time. Hydra must be pointed at the hook separately (see the ory-hydra module's token_hook variable, or ory-stack's selfservice_ui_token_hook_enabled)."
  type        = bool
  default     = false
  nullable    = false
}

variable "token_hook_api_key" {
  description = "Shared secret Hydra sends in the X-Token-Hook-Api-Key header when calling the token hook. Must be at least 32 characters. If not set and token_hook_enabled is true, a random 48-character key is generated; read it back from the token_hook_api_key output to configure Hydra."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.token_hook_api_key == null || length(coalesce(var.token_hook_api_key, "")) >= 32
    error_message = "token_hook_api_key must be at least 32 characters."
  }
}

variable "log_level" {
  description = "Log level for the selfservice service."
  type        = string
  default     = "info"
  nullable    = false

  validation {
    condition     = contains(["fatal", "error", "warn", "info", "debug", "trace"], var.log_level)
    error_message = "log_level must be one of: fatal, error, warn, info, debug, trace."
  }
}

variable "metrics_port" {
  description = "Port for the service's Prometheus metrics listener (METRICS_PORT). Served separately from the public port so the LoadBalancer never exposes it; scrape it from the pod. Null disables the listener. Must differ from var.port."
  type        = number
  default     = null

  validation {
    condition     = var.metrics_port == null || var.metrics_port != var.port
    error_message = "metrics_port must differ from port."
  }
}

variable "log_redact_pii" {
  description = "Redact personally identifiable information (email addresses, trait values) from the service's logs. Leave false while debugging sign-in issues; turn it on where logs are shipped off-cluster."
  type        = bool
  default     = false
  nullable    = false
}

variable "remember_consent_for_seconds" {
  description = "How long Hydra remembers a granted consent for, in seconds. Within this window returning users skip the consent screen."
  type        = number
  default     = 3600
  nullable    = false
}
