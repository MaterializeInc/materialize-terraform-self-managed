variable "instance_name" {
  description = "The name of the Materialize instance."
  type        = string
  nullable    = false
}

variable "name_prefix" {
  description = "Prefix to use for NLB, Target Groups, Listeners, and TargetGroupBindings"
  type        = string
  nullable    = false
}

variable "internal" {
  description = "Whether the NLB is internal only. Defaults to false (public) to allow external access to Materialize. Set to true for VPC-only access."
  type        = bool
  default     = false
  nullable    = false
}

variable "namespace" {
  description = "Kubernetes namespace in which to install TargetGroupBindings"
  type        = string
  nullable    = false
}

variable "subnet_ids" {
  description = "A list of subnet IDs in which to install the NLB. Must be in the VPC."
  type        = list(string)
  nullable    = false
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
  nullable    = false
}

variable "mz_resource_id" {
  description = "The resourceId from the Materialize CR"
  type        = string
  nullable    = false
}

variable "enable_cross_zone_load_balancing" {
  description = "Whether to enable cross zone load balancing on the NLB."
  type        = bool
  default     = true
  nullable    = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
