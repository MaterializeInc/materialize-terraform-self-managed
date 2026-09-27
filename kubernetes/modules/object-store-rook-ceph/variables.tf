variable "name" {
  description = "Name for the Ceph cluster and object store, used for resource names and labels."
  type        = string
  default     = "ceph"
}

variable "namespace" {
  description = "Namespace to deploy Rook and Ceph into. Rook expects the operator and cluster to share one."
  type        = string
  default     = "rook-ceph"
}

variable "create_namespace" {
  description = "Whether to create the namespace. Set false when another module already owns it."
  type        = bool
  default     = true
}

variable "operator_chart_version" {
  description = "Version of the rook-ceph operator Helm chart."
  type        = string
  default     = "v1.16.7"
}

variable "ceph_image" {
  description = "Ceph container image run by the daemons."
  type        = string
  default     = "quay.io/ceph/ceph:v19.2.6"
}

variable "install_timeout" {
  description = "Seconds to wait for the operator chart to install."
  type        = number
  default     = 600
}

variable "mon_count" {
  description = "Number of Ceph monitors. Three is the smallest count that tolerates losing one; use one only for a single-node test cluster."
  type        = number
  default     = 3

  validation {
    condition     = var.mon_count % 2 == 1
    error_message = "mon_count must be odd, so monitors can form a quorum."
  }
}

variable "replica_size" {
  description = "Replica count for the object store's metadata and data pools."
  type        = number
  default     = 3
}

variable "failure_domain" {
  description = "CRUSH failure domain for the object store's pools. Use `osd` only when every OSD shares a node."
  type        = string
  default     = "host"
}

variable "gateway_instances" {
  description = "Number of RGW gateway pods serving S3. This is the request path, so it is the first thing to scale for throughput."
  type        = number
  default     = 2
}

variable "osd_storage_class" {
  description = <<-EOT
    StorageClass OSDs are provisioned from, one OSD per volume.

    This is the path to use in a cloud, and the only one available once the
    node's instance store has been claimed into an LVM volume group, since Rook
    can no longer see raw devices. Point it at the class from
    `lvm-local-storage` to put OSDs on local NVMe.

    Null instead hands Rook whole devices, using `use_all_devices` and
    `device_filter`, which suits bare metal.
  EOT
  type        = string
  default     = null
}

variable "osd_count" {
  description = <<-EOT
    Number of OSDs to create from `osd_storage_class`.

    Each needs a node with room in its volume group, so this should not exceed
    the size of the storage node pool when the class is node-local. Ignored
    when `osd_storage_class` is null.
  EOT
  type        = number
  default     = 3
}

variable "osd_size" {
  description = "Size of each OSD volume. Ignored when `osd_storage_class` is null."
  type        = string
  default     = "500Gi"
}

variable "use_all_devices" {
  description = "Let Rook consume every unused device on eligible nodes. Only used when `osd_storage_class` is null."
  type        = bool
  default     = false
}

variable "device_filter" {
  description = <<-EOT
    Regex selecting which devices Rook turns into OSDs, for example `^nvme[1-9]n1$`.

    Storage-optimized instances expose their local NVMe separately from the
    root volume, and this is what keeps Rook off the root volume. Ignored when
    `use_all_devices` is true.
  EOT
  type        = string
  default     = null
}

variable "node_selector" {
  description = "Node selector for Ceph daemons. Use this to pin the store to a storage-optimized node pool."
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for Ceph daemons, so they can schedule onto a tainted storage node pool."
  type = list(object({
    key      = string
    operator = string
    value    = optional(string)
    effect   = string
  }))
  default = []
}

variable "rgw_chunk_size_bytes" {
  description = <<-EOT
    Value for `rgw_max_chunk_size` and `rgw_obj_stripe_size`.

    Both default to 4 MiB in Ceph, which splits every persist blob above that
    into several RADOS objects. persist uploads 8 MiB multipart parts and
    writes blobs up to a 128 MiB target, so the stock value turns one blob
    write into a dozen or more internal round trips. 16 MiB clears the
    multipart part size with room to spare.
  EOT
  type        = number
  default     = 16777216
}

variable "osd_memory_target_bytes" {
  description = "Value for `osd_memory_target`. Null leaves Ceph's default of 4 GiB, which is appropriate when OSDs have a node to themselves."
  type        = number
  default     = null
}

variable "extra_ceph_config" {
  description = <<-EOT
    Additional lines appended to the `[global]` section of `rook-config-override`.

    Daemons read this ConfigMap at start-up, so the module creates it before
    the cluster. Changing it afterwards needs a daemon restart to take effect.
  EOT
  type        = string
  default     = ""
}

variable "bucket" {
  description = "Bucket created for Materialize's persist data."
  type        = string
  default     = "materialize"
}

variable "object_store_user" {
  description = "Name of the CephObjectStoreUser whose credentials Materialize uses."
  type        = string
  default     = "persist"
}

variable "region" {
  description = "Region reported to S3 clients. RGW ignores it, but the AWS SDKs require one to sign requests."
  type        = string
  default     = "us-east-1"
}

variable "data_dir_host_path" {
  description = "Host path where Rook keeps daemon state. Must be writable on every node running a Ceph daemon, and empty of any previous cluster's state."
  type        = string
  default     = "/var/lib/rook"
}

variable "setup_image" {
  description = "Image used by the bucket-creation Job. Needs an `aws` CLI."
  type        = string
  default     = "amazon/aws-cli:2.31.19"
}

variable "wait_for_ready" {
  description = "Wait for the bucket Job to complete before returning. Ceph takes several minutes to reach HEALTH_OK on a fresh cluster."
  type        = bool
  default     = true
}
