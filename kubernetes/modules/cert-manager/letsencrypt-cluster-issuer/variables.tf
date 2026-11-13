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

variable "acme_server_prod" {
  description = "Issue from Let's Encrypt production instead of Let's Encrypt staging. Leave it false for the first apply, check that staging issues every certificate, then set it to true. Cannot be combined with acme_server."
  type        = bool
  nullable    = false
  default     = false
}

variable "acme_server" {
  description = "Directory URL of an ACME server other than Let's Encrypt. When null, the issuer uses Let's Encrypt staging, or production when acme_server_prod is true."
  type        = string
  default     = null

  validation {
    condition     = var.acme_server == null || !var.acme_server_prod
    error_message = "Set acme_server or acme_server_prod, not both: acme_server_prod only chooses between the Let's Encrypt servers."
  }
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
