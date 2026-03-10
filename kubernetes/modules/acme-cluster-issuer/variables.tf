variable "name_prefix" {
  description = "Prefix for the ClusterIssuer name."
  type        = string
  nullable    = false
}

variable "acme_email" {
  description = "Email address for ACME registration."
  type        = string
  nullable    = false
}

variable "acme_server" {
  description = "ACME server URL."
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
  nullable    = false
}

variable "solver_config" {
  description = "Cloud-specific DNS01 solver configuration to inject into the ClusterIssuer spec."
  type        = any
  nullable    = false
}
