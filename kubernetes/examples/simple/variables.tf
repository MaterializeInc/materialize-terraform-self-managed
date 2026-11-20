variable "kubeconfig_path" {
  description = "Path to the kubeconfig for the target cluster"
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Kubeconfig context to use. Null uses the current context."
  type        = string
  default     = null
}

variable "name_prefix" {
  description = "Prefix for named resources"
  type        = string
  default     = "materialize"
}

variable "license_key" {
  description = "Materialize license key"
  type        = string
  sensitive   = true
}

variable "metadata_backend_url" {
  description = "PostgreSQL connection URL for the metadata backend, e.g. postgres://user:pass@host:5432/materialize"
  type        = string
  sensitive   = true
}

variable "persist_backend_url" {
  description = "S3-compatible connection URL for the persist backend, e.g. s3://user:pass@bucket/prefix?endpoint=https%3A%2F%2Fhost&region=region"
  type        = string
  sensitive   = true
}

variable "operator_version" {
  description = "Version of the Materialize operator Helm chart"
  type        = string
  default     = "v26.37.0" # META: helm-chart version
}

variable "helm_chart" {
  description = "Chart name from repository or local path to chart. For local charts, set the path to the chart directory."
  type        = string
  default     = "materialize-operator"
}

variable "use_local_chart" {
  description = "Whether to use a local chart instead of one from a repository"
  type        = bool
  default     = false
}

variable "orchestratord_version" {
  description = "Orchestratord image tag override. Null uses the chart default."
  type        = string
  default     = null
}

variable "environmentd_version" {
  description = "Environmentd version override. Null uses the materialize-instance module default."
  type        = string
  default     = null
}

variable "enable_ory" {
  description = "Deploy the Ory identity stack (Kratos, Hydra, the selfservice UI and, with ory_enable_polis, Polis) into the ory namespace, reachable in-cluster only. Needs a license key with the ory entitlement, which the Ory images are pulled with, and the ory_*_dsn databases."
  type        = bool
  default     = false
  nullable    = false
}

variable "ory_enable_polis" {
  description = "Also deploy Ory Polis (the SAML-to-OIDC bridge) when enable_ory is true. Needs ory_polis_dsn."
  type        = bool
  default     = true
  nullable    = false
}

variable "ory_kratos_dsn" {
  description = "PostgreSQL connection URL for the Kratos database, e.g. postgres://user:pass@host:5432/kratos?sslmode=require. Required when enable_ory is true."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = !var.enable_ory || var.ory_kratos_dsn != null
    error_message = "ory_kratos_dsn must be set when enable_ory is true."
  }
}

variable "ory_hydra_dsn" {
  description = "PostgreSQL connection URL for the Hydra database, e.g. postgres://user:pass@host:5432/hydra?sslmode=require. Required when enable_ory is true."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = !var.enable_ory || var.ory_hydra_dsn != null
    error_message = "ory_hydra_dsn must be set when enable_ory is true."
  }
}

variable "ory_polis_dsn" {
  description = "PostgreSQL connection URL for the Polis database, e.g. postgres://user:pass@host:5432/polis?sslmode=require. Required when enable_ory and ory_enable_polis are true."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = !(var.enable_ory && var.ory_enable_polis) || var.ory_polis_dsn != null
    error_message = "ory_polis_dsn must be set when enable_ory and ory_enable_polis are true."
  }
}

variable "ory_oel_image_tag" {
  description = "Image tag for the Ory Kratos and Hydra images."
  type        = string
  # renovate: datasource=docker depName=ory-artifacts/ory-enterprise/hydra-oel registryUrl=https://ory.registry.cloud.materialize.com
  default  = "26.4.19"
  nullable = false
}
