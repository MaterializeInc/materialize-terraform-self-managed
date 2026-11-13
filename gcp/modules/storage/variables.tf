variable "project_id" {
  description = "The ID of the project where resources will be created"
  type        = string
  nullable    = false
}

variable "region" {
  description = "The region where resources will be created"
  type        = string
  nullable    = false
}

variable "prefix" {
  description = "Prefix to be used for resource names"
  type        = string
  nullable    = false
}

variable "service_account" {
  description = "Email of a service account to grant roles/storage.admin on the bucket. Required when create_hmac_key is true, since the key belongs to it. Leave null when Materialize reads the bucket natively through workload_identity."
  type        = string
  default     = null
}

variable "create_hmac_key" {
  description = "Create an HMAC key for service_account, for an S3-compatible persist URL (`s3://<access id>:<secret>@<bucket>/<prefix>?endpoint=https://storage.googleapis.com`). Set false when Materialize reads the bucket natively (`gcs://`, Materialize v26.48.0 and later) through workload_identity, so no static key exists."
  type        = bool
  default     = true
  nullable    = false

  validation {
    condition     = !var.create_hmac_key || var.service_account != null
    error_message = "create_hmac_key requires service_account, which the key belongs to."
  }
}

variable "workload_identity" {
  description = "The Kubernetes service account Materialize's environmentd and clusterd pods run as, so they read and write the bucket natively (`gcs://`, Materialize v26.48.0 and later) through GKE Workload Identity. The operator names it after the Materialize resource, in the instance namespace. When set, the module creates a Google service account with roles/storage.objectAdmin on the bucket and lets that Kubernetes service account impersonate it. Annotate the instance's service account with the workload_identity_service_account_email output."
  type = object({
    namespace            = string
    service_account_name = string
  })
  default = null
}

variable "persist_path" {
  description = "Path within the bucket that persist_backend_url points at."
  type        = string
  default     = "materialize"
  nullable    = false
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}


variable "versioning" {
  description = "Enable bucket versioning. This should be enabled for production deployments."
  type        = bool
  default     = true
  nullable    = false
}

variable "lifecycle_rules" {
  description = "List of lifecycle rules to configure"
  type = list(object({
    action = object({
      type          = string
      storage_class = optional(string)
    })
    condition = object({
      age                        = optional(number)
      created_before             = optional(string)
      with_state                 = optional(string)
      num_newer_versions         = optional(number)
      days_since_noncurrent_time = optional(number)
    })
  }))
  nullable = false
  # Matches Materialize Cloud: no storage-class tiering. Persist reads every
  # surviving blob on restart, so colder classes only add retrieval fees.
  default = [
    {
      action    = { type = "AbortIncompleteMultipartUpload" }
      condition = { age = 1 }
    }
  ]
}

variable "version_ttl" {
  description = "Delete noncurrent object versions after this many days. Null disables the rule."
  type        = number
  default     = 7
}
