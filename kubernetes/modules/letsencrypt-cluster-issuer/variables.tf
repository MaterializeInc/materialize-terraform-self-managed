variable "name_prefix" {
  description = "The name prefix to use for Kubernetes resources."
  type        = string
  nullable    = false
}

variable "acme_email" {
  description = "Email address the ACME account is registered with. The ACME server sends notices about the account to it."
  type        = string
  nullable    = false
}

variable "acme_server" {
  description = "Directory URL of the ACME server. Defaults to Let's Encrypt production; use https://acme-staging-v02.api.letsencrypt.org/directory to test without counting against production rate limits."
  type        = string
  nullable    = false
  default     = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "solvers" {
  description = "cert-manager ACME solvers, passed verbatim as the ClusterIssuer's spec.acme.solvers. Each element is one solver object in cert-manager's schema: an http01 or dns01 block and an optional selector. See https://cert-manager.io/docs/configuration/acme/ for the solver fields."
  type        = any
  nullable    = false

  validation {
    condition     = can(var.solvers[0]) && can([for solver in var.solvers : keys(solver)])
    error_message = "solvers must be a non-empty list of solver objects."
  }
}
