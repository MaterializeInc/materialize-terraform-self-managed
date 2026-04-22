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
  description = "Docker image repository for the selfservice UI."
  type        = string
  default     = "oryd/kratos-selfservice-ui-node"
  nullable    = false
}

variable "image_tag" {
  description = "Docker image tag for the selfservice UI."
  type        = string
  default     = "v25.4.0"
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
  description = "Internal URL for the Kratos public API. Example: http://kratos-public.ory.svc.cluster.local:4433"
  type        = string
  nullable    = false
}

variable "kratos_admin_url" {
  description = "Internal URL for the Kratos admin API. Example: http://kratos-admin.ory.svc.cluster.local:4434"
  type        = string
  nullable    = false
}

variable "kratos_browser_url" {
  description = "Browser-accessible URL for the Kratos public API. If not set, kratos_public_url is used."
  type        = string
  default     = null
}

variable "hydra_admin_url" {
  description = "Internal URL for the Hydra admin API. Example: http://hydra-admin.ory.svc.cluster.local:4445"
  type        = string
  nullable    = false
}

variable "cookie_secret" {
  description = "Secret for signing cookies. If not set, a random 32-character secret will be generated."
  type        = string
  default     = null
  sensitive   = true
}

variable "csrf_cookie_secret" {
  description = "Secret for CSRF cookie hashing. If not set, a random 32-character secret will be generated."
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
