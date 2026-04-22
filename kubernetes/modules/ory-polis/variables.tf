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

variable "name" {
  description = "Name prefix for Polis Kubernetes resources."
  type        = string
  default     = "polis"
  nullable    = false
}

variable "dsn" {
  description = "PostgreSQL DSN for Polis database connection. Example: postgres://user:password@host:5432/polis?sslmode=require"
  type        = string
  sensitive   = true
  nullable    = false
}

variable "replica_count" {
  description = "Number of Polis replicas."
  type        = number
  default     = 2
  nullable    = false
}

variable "port" {
  description = "Port that the Polis application listens on."
  type        = number
  default     = 5225
  nullable    = false
}

variable "image_registry" {
  description = "Docker image registry for Polis. Example: europe-docker.pkg.dev"
  type        = string
  default     = "docker.io"
  nullable    = false
}

variable "image_repository" {
  description = "Docker image repository for Polis. Example: ory-artifacts/ory-enterprise-polis/polis-oel"
  type        = string
  default     = "boxyhq/jackson"
  nullable    = false
}

variable "image_tag" {
  description = "Docker image tag for Polis."
  type        = string
  default     = "1.52.2"
  nullable    = false
}

variable "image_pull_secrets" {
  description = "List of Kubernetes secret names for pulling images from private registries. Required for OEL deployments."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "image_pull_policy" {
  description = "Image pull policy for Polis pods."
  type        = string
  default     = "IfNotPresent"
  nullable    = false
}

variable "admin_api_keys" {
  description = "API key(s) for authenticating requests to Polis admin APIs (injected into the container as the JACKSON_API_KEYS env var that upstream Polis expects). If not set, a random 32-character key will be generated."
  type        = string
  default     = null
  sensitive   = true
}

variable "saml_audience" {
  description = "SAML audience identifier (Polis's SAML entity ID). Identity providers validate that SAML assertions are intended for this audience. Must match the audience configured on the upstream IdP. Example: https://saml.example.com/entityid"
  type        = string
  nullable    = false
}

variable "external_url" {
  description = "Externally-reachable HTTPS URL for Polis. Used as the SAML ACS URL, OAuth callback base, and NextAuth URL, so it must resolve from end-user browsers. Polis does not serve TLS itself — terminate HTTPS at an ingress or LoadBalancer in front of the pod. Example: https://polis.internal.example.com"
  type        = string
  nullable    = false
}

variable "nextauth_secret" {
  description = "Secret for NextAuth.js session signing. If not set, a random 32-character secret will be generated."
  type        = string
  default     = null
  sensitive   = true
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
  description = "Additional environment variables for Polis pods as a map of name to value."
  type        = map(string)
  default     = {}
  nullable    = false
}
