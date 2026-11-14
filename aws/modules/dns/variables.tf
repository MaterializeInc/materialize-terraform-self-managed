variable "name_prefix" {
  description = "Prefix to be used for resource names"
  type        = string
  nullable    = false
}

variable "zone_id" {
  description = "ID of the existing Route 53 hosted zone. The module adds records to the zone and never creates, changes or deletes the zone itself."
  type        = string
  nullable    = false
}

variable "stem_domain" {
  description = "Domain the subdomains are created under, such as mz.example.com in the zone example.com. It must be the zone's domain or a name inside it. Defaults to the zone's domain."
  type        = string
  default     = null
}

variable "subdomains" {
  description = "Hostnames under stem_domain, keyed by the name the fqdns output uses for each. subdomain defaults to the key, and \"@\" means stem_domain itself. When create is true, the default, the module creates a record of the given type (A, AAAA or CNAME; A by default) whose values come from records under the same key. With create false it only computes the name, for a record managed elsewhere."
  type = map(object({
    subdomain = optional(string)
    create    = optional(bool, true)
    type      = optional(string, "A")
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
}

variable "records" {
  description = "Values of the record for each subdomains entry with create = true, keyed like subdomains: addresses for A and AAAA, one target name for a CNAME. They are kept out of subdomains so that the fqdns output never depends on them, which lets a load balancer configured with one of those names hand its address back here without a dependency cycle."
  type        = map(list(string))
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for key in keys(var.records) : contains(keys(var.subdomains), key)])
    error_message = "Every key in records must also be a key in subdomains."
  }
}

variable "cert_manager_dns01" {
  description = "Set to create the IAM role cert-manager's ACME DNS-01 solver assumes through IRSA, allowed only to change TXT records named _acme-challenge under stem_domain in this hosted zone, and to fill the cert_manager_service_account_annotations and acme_dns01_solver outputs. oidc_provider_arn and cluster_oidc_issuer_url come from the eks module; namespace and service_account_name are where cert-manager's controller runs. Null, the default, creates no role."
  type = object({
    oidc_provider_arn       = string
    cluster_oidc_issuer_url = string
    namespace               = optional(string, "cert-manager")
    service_account_name    = optional(string, "cert-manager")
  })
  default = null
}

variable "iam_permissions_boundary" {
  description = "ARN of the IAM permissions boundary to attach to all IAM roles created by this module. Required for BYOC deployments."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to resources created."
  type        = map(string)
  default     = {}
  nullable    = false
}
