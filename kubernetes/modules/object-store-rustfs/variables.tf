variable "name" {
  description = "Name for the RustFS release, used for the StatefulSet, services and labels."
  type        = string
  default     = "rustfs"
}

variable "namespace" {
  description = "Namespace to deploy RustFS into."
  type        = string
  default     = "object-store"
}

variable "create_namespace" {
  description = "Whether to create the namespace. Set false when another module already owns it."
  type        = bool
  default     = true
}

variable "image" {
  description = "RustFS server image."
  type        = string
  default     = "rustfs/rustfs:1.0.0-rc.5"
}

variable "replicas" {
  description = <<-EOT
    Number of RustFS server pods.

    One replica runs a single-node store against a single drive. More than one
    replica forms an erasure-coded set across the pods, which needs
    `replicas * drives_per_replica` to be at least 4. Use an odd count only if
    you know RustFS accepts the resulting set size.
  EOT
  type        = number
  default     = 1

  validation {
    condition     = var.replicas >= 1
    error_message = "replicas must be at least 1."
  }
}

variable "drives_per_replica" {
  description = <<-EOT
    Number of data volumes mounted per pod.

    Storage-optimized instances expose several local NVMe devices, and RustFS
    erasure-codes across drives as well as across pods. Each drive gets its own
    PersistentVolumeClaim from `storage_class`.
  EOT
  type        = number
  default     = 1

  validation {
    condition     = var.drives_per_replica >= 1
    error_message = "drives_per_replica must be at least 1."
  }
}

variable "drive_size" {
  description = "Size of each data volume."
  type        = string
  default     = "100Gi"
}

variable "storage_class" {
  description = <<-EOT
    StorageClass for the data volumes. Null uses the cluster default.

    For benchmarking, point this at a class backed by the node's local NVMe
    rather than network storage, or the numbers measure the network.
  EOT
  type        = string
  default     = null
}

variable "bucket" {
  description = "Bucket created for Materialize's persist data."
  type        = string
  default     = "materialize"
}

variable "access_key" {
  description = "RustFS root access key."
  type        = string
  default     = "rustfsadmin"
}

variable "secret_key" {
  description = <<-EOT
    RustFS root secret key. Null generates one.

    This is a test and benchmarking backend, so the generated value lands in
    Terraform state like any other generated credential.
  EOT
  type        = string
  default     = null
  sensitive   = true
}

variable "region" {
  description = "Region reported to S3 clients. RustFS ignores it, but the AWS SDKs require one to sign requests."
  type        = string
  default     = "us-east-1"
}

variable "resources" {
  description = "Resource requests and limits for the RustFS containers."
  type = object({
    requests = optional(map(string), { cpu = "100m", memory = "256Mi" })
    limits   = optional(map(string), {})
  })
  default = {}
}

variable "node_selector" {
  description = "Node selector for RustFS pods. Use this to pin the store to a storage-optimized node pool."
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for RustFS pods, so they can schedule onto a tainted storage node pool."
  type = list(object({
    key      = string
    operator = string
    value    = optional(string)
    effect   = string
  }))
  default = []
}

variable "rpc_secret" {
  description = <<-EOT
    Shared secret the servers authenticate to each other with. Null generates one.

    Required once the store spans more than one pod: RustFS will otherwise
    refuse to start, since it declines to derive an RPC secret from default
    root credentials.
  EOT
  type        = string
  default     = null
  sensitive   = true
}

variable "spread_across_nodes" {
  description = <<-EOT
    Require each server pod to land on a different node.

    On by default because replicas only buy durability when they sit on
    different disks, and the pods are small enough that a scheduler will
    otherwise pack them onto one node. Turn it off for a single-node cluster,
    where the constraint is unsatisfiable and the pods stay Pending forever.
    Ignored when `replicas` is 1.
  EOT
  type        = bool
  default     = true
}

variable "fs_group" {
  description = <<-EOT
    Group that owns the mounted data volumes.

    Must match the group the server image runs as, which for the upstream
    RustFS images is 10001. A mismatch shows up as the server exiting
    immediately with a permission error on its data directory.
  EOT
  type        = number
  default     = 10001
}

variable "setup_image" {
  description = "Image used by the bucket-creation Job. Needs an `aws` CLI."
  type        = string
  default     = "amazon/aws-cli:2.31.19"
}

variable "wait_for_ready" {
  description = "Wait for the StatefulSet to report ready before returning. Disable for faster plans in CI."
  type        = bool
  default     = true
}
