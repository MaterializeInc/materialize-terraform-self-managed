variable "namespace" {
  description = "Kubernetes namespace for Ory Hydra."
  type        = string
  default     = "ory-hydra"
  nullable    = false
}

variable "create_namespace" {
  description = "Whether to create the Kubernetes namespace. Set to false if the namespace already exists."
  type        = bool
  default     = true
  nullable    = false
}

variable "chart_version" {
  description = "Version of the Ory Hydra Helm chart to install."
  type        = string
  default     = "0.60.1"
  nullable    = false
}

variable "install_timeout" {
  description = "Timeout for installing the Ory Hydra Helm chart, in seconds."
  type        = number
  default     = 600
  nullable    = false
}

variable "release_name" {
  description = "Name of the Helm release."
  type        = string
  default     = "hydra"
  nullable    = false
}

variable "dsn" {
  description = "PostgreSQL DSN for Hydra database connection. Example: postgres://user:password@host:5432/hydra?sslmode=require"
  type        = string
  sensitive   = true
  nullable    = false
}

variable "secrets_system" {
  description = "System secret for signing and encryption. Must be at least 16 characters. If not set, a random 32-character secret will be generated."
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

variable "issuer_url" {
  description = "The public URL of the OAuth2 issuer. Used for OIDC discovery. Example: https://auth.example.com/"
  type        = string
  nullable    = false
}

variable "login_url" {
  description = "The URL of the login UI. Hydra redirects users here for authentication. Example: https://login.example.com/login"
  type        = string
  default     = ""
  nullable    = false
}

variable "consent_url" {
  description = "The URL of the consent UI. Hydra redirects users here for consent. Example: https://login.example.com/consent"
  type        = string
  default     = ""
  nullable    = false
}

variable "logout_url" {
  description = "The URL of the logout UI. Example: https://login.example.com/logout"
  type        = string
  default     = ""
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
  description = "Number of Hydra replicas."
  type        = number
  default     = 2
  nullable    = false
}

variable "resources" {
  description = "Resource requests and limits for Hydra pods."
  type = object({
    requests = optional(object({
      cpu    = optional(string, "250m")
      memory = optional(string, "256Mi")
    }))
    limits = optional(object({
      cpu    = optional(string, "1000m")
      memory = optional(string, "1Gi")
    }))
  })
  default = {
    requests = {}
    limits   = {}
  }
  nullable = false
}

variable "node_selector" {
  description = "Node selector for Hydra pods."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "tolerations" {
  description = "Tolerations for Hydra pods."
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
  description = "Whether to enable PodDisruptionBudget for Hydra."
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

variable "maester_enabled" {
  description = "Whether to enable hydra-maester (CRD controller for managing OAuth2 clients via Kubernetes resources)."
  type        = bool
  default     = true
  nullable    = false
}

variable "helm_values" {
  description = "Additional values to pass to the Helm chart. These will be deep-merged with the module's default values, with these values taking precedence."
  type        = any
  default     = {}
  nullable    = false
}
