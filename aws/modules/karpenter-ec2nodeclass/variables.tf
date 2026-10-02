variable "name" {
  description = "Name of the EC2NodeClass."
  type        = string
  nullable    = false
}

variable "ami_selector_terms" {
  description = "Terms for selecting which AMI to launch. See https://karpenter.sh/docs/tasks/managing-amis/ for more information. Only Bottlerocket AMIs are supported by this terraform code."
  type        = list(any)
  nullable    = false
}

variable "instance_types" {
  description = "List of instance types to support."
  type        = list(string)
  nullable    = false
}

variable "instance_profile" {
  description = "Name of the instance profile to assign to nodes."
  type        = string
  nullable    = false
}

variable "security_group_ids" {
  description = "List of security group IDs to assign to nodes."
  type        = list(string)
  nullable    = false
}

variable "subnet_ids" {
  description = "List of subnet IDs to launch nodes into."
  type        = list(string)
  nullable    = false
}

variable "tags" {
  description = "Tags to apply to AWS resources created."
  type        = map(string)
  nullable    = false
}

variable "swap_enabled" {
  description = <<-EOT
    Deprecated: use `ephemeral_storage_mode` instead.

    Whether to enable swap on the local NVMe disks. `true` selects the `swap`
    mode and `false` selects `none`; null defers to `ephemeral_storage_mode`,
    which is the default.
  EOT
  type        = bool
  default     = null
}

variable "ephemeral_storage_mode" {
  description = <<-EOT
    What to do with the instance store NVMe disks.

    `swap` adds them as swap, which is what Materialize compute nodes want so
    they can spill. `lvm` combines them into a volume group for a local CSI
    driver to provision PersistentVolumes from, which is what a storage node
    pool running an object store wants. `none` leaves them untouched.

    A node cannot do both, so run compute and storage as separate node pools,
    each with its own node class built from this module.
  EOT
  type        = string
  default     = "swap"
  nullable    = false

  validation {
    condition     = contains(["none", "swap", "lvm"], var.ephemeral_storage_mode)
    error_message = "ephemeral_storage_mode must be one of: none, swap, lvm."
  }
}

variable "ephemeral_storage_vg_name" {
  description = "Name of the LVM volume group created in `lvm` mode. A local CSI driver's StorageClass must name the same group."
  type        = string
  default     = "instance-store-vg"
  nullable    = false
}

variable "disk_setup_image" {
  description = "Docker image that configures the instance store disks, used by the `swap` and `lvm` modes."
  type        = string
  default     = "docker.io/materialize/ephemeral-storage-setup-image:v0.4.1"
  nullable    = false
}

variable "prefix_delegation_enabled" {
  description = "Whether the CNI is configured to assign CIDR block prefixes instead of single IP addresses."
  type        = bool
  default     = false
  nullable    = false
}
