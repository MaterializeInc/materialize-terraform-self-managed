variable "operator_namespace" {
  description = "The namespace where the Materialize operator is installed"
  type        = string
}

variable "instance_namespaces" {
  description = "List of namespaces where Materialize instances are deployed"
  type        = list(string)
  default     = []
}

variable "enable_default_deny" {
  description = "Enable default deny policies for operator and instance namespaces"
  type        = bool
  default     = true
}
