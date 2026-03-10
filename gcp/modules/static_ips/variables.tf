variable "project_id" {
  description = "The GCP project ID."
  type        = string
  nullable    = false
}

variable "region" {
  description = "The GCP region for the static IPs."
  type        = string
  nullable    = false
}

variable "prefix" {
  description = "Prefix for resource names."
  type        = string
  nullable    = false
}
