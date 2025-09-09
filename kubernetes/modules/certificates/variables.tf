variable "install_cert_manager" {
  description = "Whether to install cert-manager."
  type        = bool
  nullable    = false
}

variable "use_self_signed_cluster_issuer" {
  description = "Whether to install and use a self-signed ClusterIssuer for TLS. Due to limitations in Terraform, this may not be enabled before the cert-manager CRDs are installed."
  type        = bool
  default     = false
  nullable    = false
}

variable "cert_manager_namespace" {
  description = "The name of the namespace in which cert-manager is or will be installed."
  type        = string
  nullable    = false
  default     = "cert-manager"
}

variable "name_prefix" {
  description = "The name prefix to use for Kubernetes resources. Does not apply to cert-manager itself, as that is a singleton per cluster."
  type        = string
  nullable    = false
}

variable "cert_manager_install_timeout" {
  description = "Timeout for installing the cert-manager helm chart, in seconds."
  type        = number
  nullable    = false
  default     = 300
}

variable "cert_manager_chart_version" {
  description = "Version of the cert-manager helm chart to install."
  type        = string
  nullable    = false
  default     = "v1.18.0"
}
