variable "operator_version" {
  description = "Version of the Materialize operator Helm chart"
  type        = string
  default     = "v26.7.0" # META: helm-chart version
}

# For testing only - set via TF_VAR_license_key (from MATERIALIZE_LICENSE_KEY env var)
variable "license_key" {
  description = "Materialize license key for testing"
  type        = string
  sensitive   = true
  default     = ""
}
