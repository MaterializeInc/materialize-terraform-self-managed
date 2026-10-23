variable "namespace" {
  description = "Kubernetes namespace for Ory Kratos."
  type        = string
  default     = "ory-kratos"
  nullable    = false
}

variable "create_namespace" {
  description = "Whether to create the Kubernetes namespace. Set to false if the namespace already exists."
  type        = bool
  default     = true
  nullable    = false
}

variable "chart_version" {
  description = "Version of the Ory Kratos Helm chart to install."
  type        = string
  default     = "0.60.1"
  nullable    = false
}

variable "install_timeout" {
  description = "Timeout for installing the Ory Kratos Helm chart, in seconds."
  type        = number
  default     = 600
  nullable    = false
}

variable "release_name" {
  description = "Name of the Helm release."
  type        = string
  default     = "kratos"
  nullable    = false
}

variable "dsn" {
  description = "PostgreSQL DSN for Kratos database connection. Example: postgres://user:password@host:5432/kratos?sslmode=require"
  type        = string
  sensitive   = true
  nullable    = false
}

variable "secrets_default" {
  description = "Default secret for signing and encryption. If not set, a random 32-character secret will be generated."
  type        = string
  default     = null
  sensitive   = true
}

variable "secrets_cookie" {
  description = "Secret for cookie signing. If not set, a random 32-character secret will be generated."
  type        = string
  default     = null
  sensitive   = true
}

variable "secrets_cipher" {
  description = "Secret for cipher encryption. If not set, a random 32-character secret will be generated."
  type        = string
  default     = null
  sensitive   = true
}

variable "identity_schemas" {
  description = "Map of identity schema filenames to their JSON content. Example: { \"identity.default.schema.json\" = file(\"schemas/default.json\") }"
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "default_identity_schema_id" {
  description = "The default identity schema ID to use."
  type        = string
  default     = "default"
  nullable    = false
}

variable "automigration_enabled" {
  description = "Whether to enable automatic database migration."
  type        = bool
  default     = true
  nullable    = false
}

variable "automigration_type" {
  description = "Type of automigration: 'job' (Helm hook) or 'initContainer'."
  type        = string
  default     = "job"
  nullable    = false

  validation {
    condition     = contains(["job", "initContainer"], var.automigration_type)
    error_message = "Automigration type must be either 'job' or 'initContainer'."
  }
}

variable "replica_count" {
  description = "Number of Kratos replicas."
  type        = number
  default     = 2
  nullable    = false
}

variable "resources" {
  description = "Resource requests and limits for Kratos pods. By default, CPU has a request but no limit (to allow bursting), and memory request equals memory limit (to avoid OOM issues from overcommit)."
  type = object({
    requests = optional(object({
      cpu    = optional(string, "250m")
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
  description = "Node selector for Kratos pods."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "tolerations" {
  description = "Tolerations for Kratos pods."
  type = list(object({
    key      = string
    value    = optional(string)
    operator = optional(string, "Equal")
    effect   = string
  }))
  default  = []
  nullable = false
}

variable "pdb_enabled" {
  description = "Whether to enable PodDisruptionBudget for Kratos."
  type        = bool
  default     = true
  nullable    = false
}

variable "pdb_min_available" {
  description = "Minimum number of available pods during disruptions."
  type        = number
  default     = 1
  nullable    = false
}

variable "smtp_connection_uri" {
  description = "SMTP connection URI for sending emails. Example: smtp://user:password@smtp.example.com:587/"
  type        = string
  default     = null
  sensitive   = true
}

variable "smtp_from_address" {
  description = "Email address used as the sender for Kratos emails."
  type        = string
  default     = null
}

variable "smtp_from_name" {
  description = "Name used as the sender for Kratos emails."
  type        = string
  default     = null
}

variable "image_repository" {
  description = "Override the Docker image repository for Kratos. Must include the full registry path as the Ory Helm chart ignores image.registry. Example: europe-docker.pkg.dev/ory-artifacts/ory-enterprise-kratos/kratos-oel"
  type        = string
  default     = null
}

variable "image_tag" {
  description = "Override the Docker image tag for Kratos. If not set, the chart default will be used."
  type        = string
  default     = null
}

variable "image_pull_secrets" {
  description = "List of Kubernetes secret names for pulling images from private registries. Required for OEL deployments."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "tls_cert_secret_name" {
  description = "Name of a Kubernetes TLS secret (containing tls.crt and tls.key) to mount into the Kratos container and serve HTTPS from. Typically created by cert-manager. When set, Kratos's public API serves TLS directly."
  type        = string
  default     = null
}

variable "upstream_identity_providers" {
  description = <<-EOT
    Upstream identity providers to expose as social sign-in methods on the Kratos selfservice UI. Each entry renders as a 'Sign in with X' button. Leave as [] to keep password-only login. For provider = "generic" the redirect URI to register at the IdP is <kratos public URL>/self-service/methods/oidc/callback/<id>. For provider = "jackson" (Ory Polis, the SAML-to-OIDC bridge) the callback is registered under the SAML method base instead, <kratos public URL>/self-service/methods/saml/callback/<id>.

    Each provider gets its own claim mapper, so it can only sign in the users and grant the groups configured on it:
    - allowed_email_domains (required): email domains this provider may sign in, e.g. ["example.com"]. Matched exactly against the lowercased email, so subdomains need their own entry. Sign-in with any other domain fails.
    - allowed_groups: if set, only these groups are kept from the provider's groups claim.
    - group_prefix: if set, only groups starting with it are kept. With both set, a group must pass both.
    - require_email_verified (default true): refuse sign-in unless the provider marks the email verified (email_verified true or "true"). Microsoft Entra ID does not send email_verified by default; set false there and rely on allowed_email_domains.
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

  validation {
    condition = alltrue([
      for p in var.upstream_identity_providers : length(p.allowed_email_domains) > 0 && alltrue([
        for d in p.allowed_email_domains : can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", d))
      ])
    ])
    error_message = "Every upstream_identity_providers entry needs a non-empty allowed_email_domains of lowercase domains, e.g. [\"example.com\"] (no '@', wildcard or trailing dot)."
  }
}

variable "saml_providers" {
  description = "SAML sign-in providers exposed via the Kratos SAML method (selfservice.methods.saml), used for Ory Polis (the jackson SAML-to-OIDC bridge). Each entry renders as a 'Sign in with X' button whose SAML callback is <kratos public URL>/self-service/methods/saml/callback/<id>. Leave as [] when no SAML sign-in is configured. Use this instead of upstream_identity_providers for Polis, since jackson is a SAML method rather than an OIDC provider. allowed_email_domains, allowed_groups, group_prefix and require_email_verified work as in upstream_identity_providers, except that require_email_verified defaults to false: SAML assertions carry no email_verified claim. Kratos always uses PKCE towards Polis."
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

  validation {
    condition = alltrue([
      for p in var.saml_providers : length(p.allowed_email_domains) > 0 && alltrue([
        for d in p.allowed_email_domains : can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", d))
      ])
    ])
    error_message = "Every saml_providers entry needs a non-empty allowed_email_domains of lowercase domains, e.g. [\"example.com\"] (no '@', wildcard or trailing dot)."
  }
}

variable "saml_base_redirect_uri" {
  description = "The Kratos public base URL used as the SAML method's base_redirect_uri. Example: https://ory.example.com/kratos"
  type        = string
  default     = null
}

variable "helm_values" {
  description = "Additional values to pass to the Helm chart. These will be deep-merged with the module's default values, with these values taking precedence."
  type        = any
  default     = {}
  nullable    = false
}

variable "enable_service_monitor" {
  description = "Create a ServiceMonitor for Kratos's admin metrics. The prometheus-operator CRDs must be installed before this module, or the chart leaves it out. The scraper must reach the admin port, which serves Kratos's whole admin API beside the metrics, so route it through a metrics-only proxy with service_monitor_relabelings rather than admitting the scraper to that port."
  type        = bool
  default     = false
  nullable    = false
}

variable "service_monitor_relabelings" {
  description = "Prometheus relabelings applied to the ServiceMonitor's endpoint, e.g. to scrape through a proxy instead of the admin port."
  type        = any
  default     = []
  nullable    = false
}

variable "cleanup_enabled" {
  description = "Run Kratos's cleanup CronJob (kratos cleanup sql), which deletes expired sessions, flows and continuity rows. Kratos never deletes them otherwise, so its tables grow with every sign-in."
  type        = bool
  default     = true
  nullable    = false
}

variable "cleanup_schedule" {
  description = "Cron schedule for the cleanup CronJob."
  type        = string
  default     = "17 * * * *"
  nullable    = false
}
