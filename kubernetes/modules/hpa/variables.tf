variable "name" {
  description = "Name of the HPA resource"
  type        = string
  nullable    = false
}

variable "namespace" {
  description = "Namespace for the HPA"
  type        = string
  nullable    = false
}

variable "target_name" {
  description = "Name of the resource to scale"
  type        = string
  nullable    = false
}

variable "target_kind" {
  description = "Kind of the resource to scale (Deployment, StatefulSet, ReplicaSet)"
  type        = string
  nullable    = false

  validation {
    condition     = contains(["Deployment", "StatefulSet", "ReplicaSet"], var.target_kind)
    error_message = "target_kind must be one of: Deployment, StatefulSet, ReplicaSet"
  }
}


variable "min_replicas" {
  description = "Minimum number of replicas"
  type        = number
  default     = 2
  nullable    = false
}

variable "max_replicas" {
  description = "Maximum number of replicas"
  type        = number
  default     = 100
  nullable    = false
}

variable "cpu_target_utilization" {
  description = "Target CPU utilization percentage"
  type        = number
  default     = 60
  nullable    = false
}

variable "memory_target_utilization" {
  description = "Target memory utilization percentage"
  type        = number
  default     = 50
  nullable    = false
}

variable "scale_up_stabilization_window" {
  description = "Stabilization window for scale up in seconds"
  type        = number
  default     = 180
  nullable    = false
}

variable "scale_down_stabilization_window" {
  description = "Stabilization window for scale down in seconds"
  type        = number
  default     = 600
  nullable    = false
}

variable "scale_up_pods_per_period" {
  description = "Maximum pods to add per period during scale up"
  type        = number
  default     = 4
  nullable    = false
}

variable "scale_up_percent_per_period" {
  description = "Maximum percent to scale up per period"
  type        = number
  default     = 100
  nullable    = false
}

variable "scale_down_percent_per_period" {
  description = "Maximum percent to scale down per period"
  type        = number
  default     = 100
  nullable    = false
}

variable "policy_period_seconds" {
  description = "Period in seconds for scaling policies"
  type        = number
  default     = 15
  nullable    = false
}
