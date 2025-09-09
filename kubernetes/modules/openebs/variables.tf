variable "openebs_namespace" {
  description = "Namespace for OpenEBS components"
  type        = string
  default     = "openebs"
  nullable    = false
}

variable "create_openebs_namespace" {
  description = "Whether to create the OpenEBS namespace. Set to false if the namespace already exists."
  type        = bool
  default     = true
  nullable    = false
}

variable "openebs_version" {
  description = "Version of OpenEBS Helm chart to install"
  type        = string
  default     = "4.2.0"
  nullable    = false
}

variable "install_openebs" {
  description = "Whether to install OpenEBS"
  type        = bool
  default     = true
  nullable    = false
}

variable "install_openebs_crds" {
  description = "Whether to install OpenEBS CRDs"
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_mayastor" {
  description = "Whether to enable Mayastor in OpenEBS"
  type        = bool
  default     = false
  nullable    = false
}
