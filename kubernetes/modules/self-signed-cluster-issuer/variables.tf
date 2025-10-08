variable "namespace" {
  description = "The namespace in which to create the root CA certificate object."
  type        = string
  nullable    = false
  default     = "cert-manager"
}

variable "name_prefix" {
  description = "The name prefix to use for Kubernetes resources."
  type        = string
  nullable    = false
}
