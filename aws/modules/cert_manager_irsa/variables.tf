variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  nullable    = false
}

variable "oidc_provider_arn" {
  description = "The ARN of the OIDC provider for the EKS cluster."
  type        = string
  nullable    = false
}

variable "cluster_oidc_issuer_url" {
  description = "The OIDC issuer URL of the EKS cluster."
  type        = string
  nullable    = false
}

variable "hosted_zone_id" {
  description = "The Route53 hosted zone ID that cert-manager needs to manage."
  type        = string
  nullable    = false
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
