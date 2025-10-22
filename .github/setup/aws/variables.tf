variable "profile" {
  description = "The AWS CLI profile to use for authentication"
  type        = string
  default     = "default"
}

variable "oidc_provider_arn" {
  description = "The ARN of the OIDC provider for GitHub Actions"
  type        = string
}
