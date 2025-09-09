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
  description = "Port for the NLB listener and Kubernetes service"
  type        = number
  nullable    = false
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
