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

variable "console_ingress_cidr_blocks" {
  description = "CIDR blocks allowed to reach the console listener, in place of `ingress_cidr_blocks`. Null uses `ingress_cidr_blocks`."
  type        = list(string)
  default     = null

  validation {
    condition = var.console_ingress_cidr_blocks == null || (length(coalesce(var.console_ingress_cidr_blocks, [])) > 0 && alltrue([
      for cidr in coalesce(var.console_ingress_cidr_blocks, []) : can(cidrhost(cidr, 0))
    ]))
    error_message = "console_ingress_cidr_blocks must be null, or non-empty and contain valid CIDR notation."
  }
}

variable "balancerd_ingress_cidr_blocks" {
  description = "CIDR blocks allowed to reach the pgwire (6875) and HTTP API (6876) listeners, in place of `ingress_cidr_blocks`. Null uses `ingress_cidr_blocks`."
  type        = list(string)
  default     = null

  validation {
    condition = var.balancerd_ingress_cidr_blocks == null || (length(coalesce(var.balancerd_ingress_cidr_blocks, [])) > 0 && alltrue([
      for cidr in coalesce(var.balancerd_ingress_cidr_blocks, []) : can(cidrhost(cidr, 0))
    ]))
    error_message = "balancerd_ingress_cidr_blocks must be null, or non-empty and contain valid CIDR notation."
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

variable "console_listener_port" {
  description = "External port the NLB listens on for the Materialize console. Defaults to 8080. Set to 443 for enterprise SSO deployments so browser OIDC redirects hit the canonical HTTPS port; the target group still forwards to the console pod on 8080."
  type        = number
  default     = 8080
  nullable    = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
