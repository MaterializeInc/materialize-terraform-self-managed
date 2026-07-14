variable "name" {
  description = "Name for Target Groups and TargetGroupBindings"
  type        = string
  nullable    = false
}

variable "nlb_arn" {
  description = "ARN of the NLB"
  type        = string
  nullable    = false
}

variable "namespace" {
  description = "Kubernetes namespace in which to install TargetGroupBindings"
  type        = string
  nullable    = false
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
  nullable    = false
}

variable "port" {
  description = "Port on the target (Kubernetes service and target group). By default the NLB listener also uses this port; override listener_port to expose a different port externally (e.g. 443 -> 8080)."
  type        = number
  nullable    = false
}

variable "listener_port" {
  description = "Port the NLB listener binds to. Defaults to var.port when null; set explicitly to expose the target on a different external port."
  type        = number
  default     = null
}

variable "health_check_path" {
  description = "The URL path for target group health checks"
  type        = string
  nullable    = false
}

variable "service_name" {
  description = "The name of the Kubernetes service to connect to"
  type        = string
  nullable    = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "preserve_client_ip" {
  description = "Whether to preserve the client IP address"
  type        = bool
  default     = true
  nullable    = false
}
