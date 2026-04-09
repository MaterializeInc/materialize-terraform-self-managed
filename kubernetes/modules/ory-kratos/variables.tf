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

variable "image_registry" {
  description = "Override the Docker image registry for Kratos. Used for OEL (Ory Enterprise License) deployments. Example: europe-docker.pkg.dev"
  type        = string
  default     = null
}

variable "image_repository" {
  description = "Override the Docker image repository for Kratos. Used for OEL deployments. Example: ory-artifacts/ory-enterprise-kratos/kratos-oel"
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

variable "helm_values" {
  description = "Additional values to pass to the Helm chart. These will be deep-merged with the module's default values, with these values taking precedence."
  type        = any
  default     = {}
  nullable    = false
}
