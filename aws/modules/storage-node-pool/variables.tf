variable "name" {
  description = "Name for the node class, node pool and the label that selects its nodes."
  type        = string
  default     = "storage"
}

variable "instance_types" {
  description = <<-EOT
    Instance types for the pool.

    Needs a family with local NVMe, since the point of this module is to keep a
    workload off EBS: the `i` families qualify, `m`/`c`/`r` generally do not.
    Every type listed must appear in the node class module's
    `instance-descriptions.json`, which is what sizes the kubelet reservations.
  EOT
  type        = list(string)
  default     = ["i8g.2xlarge"]
}

variable "limits" {
  description = "Resource ceiling for the pool. Karpenter stops adding nodes once the pool reaches it."
  type        = map(string)
  default     = { cpu = "64" }
}

variable "ami_selector_terms" {
  description = "AMI selector terms for the node class."
  type        = any
  default     = [{ "alias" : "bottlerocket@latest" }]
}

variable "instance_profile" {
  description = "Instance profile for the nodes, from the karpenter module."
  type        = string
}

variable "security_group_ids" {
  description = "Security groups for the nodes, normally the EKS node security group."
  type        = list(string)
}

variable "subnet_ids" {
  description = "Subnets the nodes may launch into. Private subnets across AZs."
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
  description = <<-EOT
    Whether this pool installs the LVM CSI driver.

    The driver is cluster-scoped and serves every pool through a shared node
    label, so exactly one pool on a cluster should install it. A second pool
    sets this false and reuses the first pool's `storage_class_name`.
  EOT
  type        = bool
  default     = true
}
