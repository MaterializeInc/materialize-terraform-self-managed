variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository in format 'owner/repo-name'"
  type        = string
  default     = "MaterializeInc/materialize-terraform-self-managed"
}
