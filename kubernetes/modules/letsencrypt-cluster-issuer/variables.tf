variable "name" {
  description = "Name of the ClusterIssuer to create. Used as a prefix for the ACME account key Secret and the DNS provider credential Secret."
  type        = string
  default     = "letsencrypt"
  nullable    = false
}

variable "namespace" {
  description = "Namespace where DNS provider credential Secrets are created. Should be the cert-manager namespace so that cert-manager can read the Secrets when solving challenges."
  type        = string
  default     = "cert-manager"
  nullable    = false
}

variable "email" {
  description = "Contact email used for Let's Encrypt account registration. Let's Encrypt sends expiry warnings and account notifications here."
  type        = string
  nullable    = false
}

variable "acme_environment" {
  description = "Let's Encrypt environment. Use 'staging' while iterating to avoid the production rate limits (50 certs/week per registered domain). Staging certs are signed by an untrusted CA so browsers will warn. Switch to 'production' once the integration is stable."
  type        = string
  default     = "staging"
  nullable    = false

  validation {
    condition     = contains(["staging", "production"], var.acme_environment)
    error_message = "acme_environment must be 'staging' or 'production'."
  }
}

variable "dns_provider" {
  description = "DNS provider used to satisfy ACME dns-01 challenges. Only 'cloudflare' is supported today; other providers can be added by extending this module."
  type        = string
  default     = "cloudflare"
  nullable    = false

  validation {
    condition     = contains(["cloudflare"], var.dns_provider)
    error_message = "dns_provider must be 'cloudflare'."
  }
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:Read and DNS:Edit permission, scoped to the zone(s) listed in dns_zones. Required when dns_provider is 'cloudflare'. Create one at https://dash.cloudflare.com/profile/api-tokens."
  type        = string
  default     = null
  sensitive   = true
}

variable "dns_zones" {
  description = "DNS zones (apex domains) the issuer is allowed to solve challenges for. Used as the dnsZones selector on the solver so the ClusterIssuer only attempts challenges for hostnames inside these zones. Example: [\"bobby.sh\"]."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.dns_zones) > 0
    error_message = "dns_zones must contain at least one zone."
  }
}
