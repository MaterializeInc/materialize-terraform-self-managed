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
  description = "Whether the NLB is internal only. Defaults to true (private) to allow internal access to Materialize. Set to false for public access."
  type        = bool
  default     = true
  nullable    = false
}

variable "ingress_cidr_blocks" {
  description = "List of CIDR blocks to allow ingress to the NLB Security Group."
  type        = list(string)
  nullable    = true
  default     = ["0.0.0.0/0"]

  validation {
    condition = var.internal ? true : (
      var.ingress_cidr_blocks != null && alltrue([
        for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))
      ])
    )
    error_message = "ingress_cidr_blocks must be provided and contain valid CIDR notation when creating a public load balancer (internal = false)."
  }
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

variable "node_security_group_id" {
  description = "ID of the EKS Node Security Group to allow traffic to. Used to add ingress rules from the NLB SG."
  type        = string
  nullable    = false
}

variable "enable_cross_zone_load_balancing" {
  description = "Whether to enable cross zone load balancing on the NLB."
  type        = bool
  default     = true
  nullable    = false
}

variable "nlb_name" {
  description = "Explicit name for the NLB. If set, uses this instead of name_prefix. Use when a specific, predictable NLB name is required."
  type        = string
  default     = null
}

variable "create_security_group" {
  description = "Whether to create a dedicated security group for the NLB with ingress rules for Materialize ports. Set to false if security groups are managed externally or not needed."
  type        = bool
  default     = true
  nullable    = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
