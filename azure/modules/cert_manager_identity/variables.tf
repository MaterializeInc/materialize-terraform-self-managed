variable "prefix" {
  description = "Prefix for resource names."
  type        = string
  nullable    = false
}

variable "resource_group_name" {
  description = "The resource group for the managed identity."
  type        = string
  nullable    = false
}

variable "location" {
  description = "The Azure region."
  type        = string
  nullable    = false
}

variable "oidc_issuer_url" {
  description = "The OIDC issuer URL of the AKS cluster."
  type        = string
  nullable    = false
}

variable "dns_zone_name" {
  description = "The name of the Azure DNS zone."
  type        = string
  nullable    = false
}

variable "dns_zone_resource_group" {
  description = "The resource group containing the DNS zone. Defaults to the same resource group."
  type        = string
  default     = null
}

variable "cert_manager_namespace" {
  description = "The Kubernetes namespace where cert-manager is installed."
  type        = string
  default     = "cert-manager"
  nullable    = false
}

variable "cert_manager_service_account_name" {
  description = "The name of the cert-manager Kubernetes service account."
  type        = string
  default     = "cert-manager"
  nullable    = false
}

variable "tags" {
  description = "Tags to apply to resources."
  type        = map(string)
  default     = {}
  nullable    = false
}
