variable "prefix" {
  description = "Prefix to be used for resource names"
  type        = string
  nullable    = false
}

variable "zone_name" {
  description = "Name of the existing Azure DNS zone, such as example.com. The module adds records to the zone and never creates, changes or deletes the zone itself."
  type        = string
  nullable    = false
}

variable "zone_resource_group_name" {
  description = "Resource group that holds the DNS zone, in the subscription the azurerm provider is configured for."
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
  description = "Set to create the user-assigned managed identity cert-manager's ACME DNS-01 solver acts as through Azure Workload Identity, with DNS Zone Contributor on this zone only, and to fill the cert_manager_pod_labels and acme_dns01_solver outputs. oidc_issuer_url comes from the aks module, and the identity is created in resource_group_name and location. namespace and service_account_name are where cert-manager's controller runs, and environment is the Azure cloud cert-manager talks to. Null, the default, creates no identity."
  type = object({
    oidc_issuer_url      = string
    resource_group_name  = string
    location             = string
    namespace            = optional(string, "cert-manager")
    service_account_name = optional(string, "cert-manager")
    environment          = optional(string, "AzurePublicCloud")
  })
  default = null

  validation {
    condition     = var.cert_manager_dns01 == null || contains(["AzurePublicCloud", "AzureChinaCloud", "AzureUSGovernmentCloud"], try(var.cert_manager_dns01.environment, ""))
    error_message = "cert_manager_dns01.environment must be AzurePublicCloud, AzureChinaCloud or AzureUSGovernmentCloud."
  }
}

variable "tags" {
  description = "Tags to apply to resources created."
  type        = map(string)
  default     = {}
  nullable    = false
}
