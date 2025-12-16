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
  description = "Whether to enable swap on the local NVMe disks."
  type        = bool
  default     = true
  nullable    = false
}

variable "disk_setup_image" {
  description = "Docker image for disk bootstraping when swap is enabled."
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
