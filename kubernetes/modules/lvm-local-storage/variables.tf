variable "namespace" {
  description = "Namespace to deploy the LVM CSI driver into."
  type        = string
  default     = "openebs"
}

variable "create_namespace" {
  description = "Whether to create the namespace. Set false when another module already owns it."
  type        = bool
  default     = true
}

variable "chart_version" {
  description = "Version of the openebs lvm-localpv Helm chart."
  type        = string
  default     = "1.6.2"
}

variable "install_timeout" {
  description = "Seconds to wait for the chart to install."
  type        = number
  default     = 600
}

variable "storage_class_name" {
  description = "Name of the StorageClass created for LVM-backed volumes."
  type        = string
  default     = "instance-store"
}

variable "volume_group" {
  description = <<-EOT
    LVM volume group the driver carves volumes out of.

    Must match `ephemeral_storage_vg_name` on the node class that ran
    `ephemeral-storage-setup lvm`, or the driver will find no group to
    provision from and PVCs will stay Pending.
  EOT
  type        = string
  default     = "instance-store-vg"
}

variable "fs_type" {
  description = "Filesystem written onto provisioned logical volumes."
  type        = string
  default     = "ext4"
}

variable "is_default_class" {
  description = <<-EOT
    Whether to mark this StorageClass default.

    Leave false on AWS, where the EBS CSI driver's `gp3` class is already the
    default. A local volume pins its pod to one node for the pod's lifetime,
    which is right for an object store and wrong for most other workloads.
  EOT
  type        = bool
  default     = false
}

variable "node_selector" {
  description = "Node selector for the CSI node plugin. Restrict this to the pool whose nodes actually have a volume group."
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for the CSI node plugin, so it can run on a tainted storage node pool."
  type = list(object({
    key      = string
    operator = string
    value    = optional(string)
    effect   = string
  }))
  default = []
}
