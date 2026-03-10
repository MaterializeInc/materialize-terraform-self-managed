variable "project_id" {
  description = "The GCP project ID."
  type        = string
  nullable    = false
}

variable "dns_zone_name" {
  description = "The name of the Cloud DNS managed zone."
  type        = string
  nullable    = false
}

variable "service_account_name" {
  description = "The name for the cert-manager Google service account."
  type        = string
  nullable    = false
}

variable "cert_manager_namespace" {
  description = "The Kubernetes namespace where cert-manager is installed."
  type        = string
  default     = "cert-manager"
  nullable    = false
}
