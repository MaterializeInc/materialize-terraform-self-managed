variable "github_repository" {
  description = "GitHub repository in format 'owner/repo-name'"
  type        = string
  default     = "MaterializeInc/materialize-terraform-self-managed"
}

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "tenant_id" {
  description = "Azure tenant ID"
  type        = string
}
