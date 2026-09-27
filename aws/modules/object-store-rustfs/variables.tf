variable "name" {
  description = "Name prefix for the store, its node pool and their labels."
  type        = string
  default     = "rustfs"
}

variable "namespace" {
  description = "Namespace to deploy RustFS into."
  type        = string
  default     = "object-store"
}

variable "image" {
  description = "RustFS server image."
  type        = string
  default     = "rustfs/rustfs:1.0.0-rc.5"
}

variable "bucket" {
  description = "Bucket created for Materialize's persist data."
  type        = string
  default     = "materialize"
}

variable "region" {
  description = "Region reported to S3 clients. RustFS ignores it, but the AWS SDKs require one to sign requests."
  type        = string
  default     = "us-east-1"
}

variable "replicas" {
  description = <<-EOT
    RustFS server pods.

    Each claims a volume from the instance store of the node it lands on, so
    this should not exceed the number of nodes the pool will run. More than one
    replica erasure-codes across pods, which needs `replicas *
    drives_per_replica` to be at least 4.
  EOT
  type        = number
  default     = 4
}

variable "drives_per_replica" {
  description = "Volumes per pod. One suits the single-NVMe instance families; raise it only on a family with several devices per node."
  type        = number
  default     = 1
}

variable "drive_size" {
  description = "Size of each volume."
  type        = string
  default     = "500Gi"
}

# --- Node pool -------------------------------------------------------------

variable "instance_types" {
  description = "Instance types for the storage node pool. Needs a family with local NVMe."
  type        = list(string)
  default     = ["i8g.2xlarge"]
}

variable "node_limits" {
  description = "Resource ceiling for the storage node pool."
  type        = map(string)
  default     = { cpu = "64" }
}

variable "ami_selector_terms" {
  description = "AMI selector terms for the storage node class."
  type        = any
  default     = [{ "alias" : "bottlerocket@latest" }]
}

variable "instance_profile" {
  description = "Instance profile for storage nodes, from the karpenter module."
  type        = string
}

variable "security_group_ids" {
  description = "Security groups for storage nodes, normally the EKS node security group."
  type        = list(string)
}

variable "subnet_ids" {
  description = "Subnets storage nodes may launch into. Private subnets across AZs."
  type        = list(string)
}

variable "kubeconfig_data" {
  description = "Contents of the kubeconfig, used by the node pool module to clean up EC2 instances on destroy."
  type        = string
}

variable "tags" {
  description = "Tags applied to the node class."
  type        = map(string)
  default     = {}
}

variable "volume_group" {
  description = "Name of the LVM volume group built from the instance store."
  type        = string
  default     = "instance-store-vg"
}

variable "storage_class_name" {
  description = "Name of the StorageClass provisioned from the volume group."
  type        = string
  default     = "instance-store"
}

variable "lvm_chart_version" {
  description = "Version of the openebs lvm-localpv Helm chart."
  type        = string
  default     = "1.6.2"
}

variable "install_csi_driver" {
  description = "Whether this store's node pool installs the LVM CSI driver. Set false for a second store sharing a cluster with one that already did."
  type        = bool
  default     = true
}
