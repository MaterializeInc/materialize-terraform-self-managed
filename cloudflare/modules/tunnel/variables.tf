variable "account_id" {
  description = "Cloudflare account ID that owns the tunnel and the Access applications."
  type        = string
}

variable "zone_id" {
  description = "ID of the Cloudflare zone the hostnames are created in."
  type        = string
}

variable "name" {
  description = "Name of the tunnel. Also used to name the Access applications and policy."
  type        = string
}

variable "console_hostname" {
  description = "Public hostname for the Materialize console. Must be covered by the zone's edge certificate; on a Universal SSL zone that means a single label under the apex (for example `mz-console.example.com`)."
  type        = string
}

variable "console_origin" {
  description = "Origin URL cloudflared forwards console traffic to, for example `https://10.0.0.5:8080`."
  type        = string
}

variable "sql_hostname" {
  description = "Public hostname for pgwire. Clients reach it with `cloudflared access tcp`. Set to null to expose only the console."
  type        = string
  default     = null
}

variable "sql_origin" {
  description = "Origin cloudflared forwards pgwire traffic to, for example `tcp://10.0.0.6:6875`. Required when `sql_hostname` is set."
  type        = string
  default     = null

  validation {
    condition     = var.sql_origin == null || startswith(coalesce(var.sql_origin, "x"), "tcp://")
    error_message = "sql_origin must use the tcp:// scheme."
  }
}

variable "origin_no_tls_verify" {
  description = "Skip verifying the origin's TLS certificate. Needed while the console serves a self-signed certificate."
  type        = bool
  default     = false
}

variable "access_email_domains" {
  description = "Email domains allowed through Cloudflare Access."
  type        = list(string)
  default     = []
}

variable "access_emails" {
  description = "Individual email addresses allowed through Cloudflare Access."
  type        = list(string)
  default     = []
}

variable "allowed_idps" {
  description = "IDs of the Access identity providers offered on the login page. Name them explicitly: with an empty list, a login method added to the account later (for example one-time PIN) was not offered."
  type        = list(string)
  default     = []
}

variable "session_duration" {
  description = "How long an Access session lasts before users must log in again."
  type        = string
  default     = "24h"
}

variable "create_service_token" {
  description = "Create an Access service token allowed through both applications, for machine clients (dbt, BI tools, CI) that cannot complete an interactive IdP login."
  type        = bool
  default     = false
}

variable "service_token_duration" {
  description = "Lifetime of the service token, for example `8760h`."
  type        = string
  default     = "8760h"
}

variable "enable_one_time_pin" {
  description = "Create Cloudflare's email one-time PIN login method and offer it on both applications, alongside `allowed_idps`. Useful when no IdP is configured, or the configured one is broken. Cloudflare allows one per account: if the account already has one, leave this false and pass its ID in `allowed_idps`. It is account-wide, so destroying this module removes it for every application."
  type        = bool
  default     = false
}
