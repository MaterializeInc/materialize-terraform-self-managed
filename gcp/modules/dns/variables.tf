variable "project_id" {
  description = "GCP project the GKE cluster runs in. The cert-manager Google service account is created here, and its Workload Identity binding uses this project's pool."
  type        = string
  nullable    = false
}

variable "prefix" {
  description = "Prefix to be used for resource names"
  type        = string
  nullable    = false
}

variable "zone_name" {
  description = "Name of the existing Cloud DNS managed zone, as Cloud DNS lists it, not its DNS name. The module adds records to the zone and never creates, changes or deletes the zone itself."
  type        = string
  nullable    = false
}

variable "zone_project_id" {
  description = "Project that holds the managed zone. Defaults to project_id."
  type        = string
  default     = null
}

variable "stem_domain" {
  description = "Domain the subdomains are created under, such as mz.example.com in the zone example.com. It must be the zone's domain or a name inside it. Defaults to the zone's domain."
  type        = string
  default     = null
}

variable "subdomains" {
  description = "Hostnames under stem_domain, keyed by the name the fqdns output uses for each. subdomain defaults to the key, and \"@\" means stem_domain itself. When create is true, the default, the module creates a record of the given type (A, AAAA or CNAME; A by default) with records as its values. With create false it only computes the name, for a record managed elsewhere."
  type = map(object({
    subdomain = optional(string)
    create    = optional(bool, true)
    type      = optional(string, "A")
    records   = optional(list(string), [])
    ttl       = optional(number, 300)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for key, entry in var.subdomains :
      can(regex("^(@|[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*)$", coalesce(entry.subdomain, key)))
    ])
    error_message = "Each subdomain (or its key, when subdomain is unset) must be \"@\" or lowercase DNS labels separated by dots."
  }

  validation {
    condition     = alltrue([for entry in values(var.subdomains) : contains(["A", "AAAA", "CNAME"], entry.type)])
    error_message = "type must be A, AAAA or CNAME."
  }

  validation {
    condition = alltrue([
      for entry in values(var.subdomains) :
      !entry.create || (entry.type == "CNAME" ? length(entry.records) == 1 : length(entry.records) > 0)
    ])
    error_message = "A subdomain with create = true needs records: one for a CNAME, at least one for A or AAAA."
  }
}

variable "cert_manager_dns01" {
  description = "Set to create the Google service account cert-manager's ACME DNS-01 solver acts as through GKE Workload Identity, with roles/dns.admin on the managed zone only, and to fill the cert_manager_service_account_annotations and acme_dns01_solver outputs. namespace and service_account_name are where cert-manager's controller runs. Null, the default, creates no identity."
  type = object({
    namespace            = optional(string, "cert-manager")
    service_account_name = optional(string, "cert-manager")
  })
  default = null
}
