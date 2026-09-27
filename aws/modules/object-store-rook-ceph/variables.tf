variable "name" {
  description = "Name prefix for the Ceph cluster, object store, node pool and their labels."
  type        = string
  default     = "ceph"
}

variable "bucket" {
  description = "Bucket created for Materialize's persist data."
  type        = string
  default     = "materialize"
}

variable "region" {
  description = "Region reported to S3 clients. RGW ignores it, but the AWS SDKs require one to sign requests."
  type        = string
  default     = "us-east-1"
}

variable "osd_count" {
  description = <<-EOT
    Number of OSDs, one per volume from the storage class.

    Each needs a node with room in its volume group, so this should not exceed
    the number of nodes the pool will run.
  EOT
  type        = number
  default     = 4
}

variable "osd_size" {
  description = "Size of each OSD volume."
  type        = string
  default     = "500Gi"
}

variable "replica_size" {
  description = "Replica count for the object store's metadata and data pools."
  type        = number
  default     = 3
}

variable "mon_count" {
  description = "Number of Ceph monitors. Three is the smallest count that tolerates losing one."
  type        = number
  default     = 3
}

variable "gateway_instances" {
  description = "Number of RGW gateway pods serving S3. This is the request path, so it is the first thing to scale for throughput."
  type        = number
  default     = 2
}

variable "rgw_chunk_size_bytes" {
  description = <<-EOT
    Value for `rgw_max_chunk_size` and `rgw_obj_stripe_size`.

    Both default to 4 MiB in Ceph, which splits every persist blob above that
    into several RADOS objects. persist uploads 8 MiB multipart parts and writes
    blobs up to a 128 MiB target, so the stock value turns one blob write into a
    dozen or more internal round trips.
  EOT
  type        = number
  default     = 16777216
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

# A mon restores its identity from this path, so a cluster pointed at a path a
# previous one used comes up as that previous cluster. Naming a fresh path here
# is the alternative to wiping the old one on every node that outlives it.
variable "data_dir_host_path" {
  description = "Host path where Rook keeps daemon state. Must be empty of any previous cluster's state."
  type        = string
  default     = "/var/lib/rook"
}
