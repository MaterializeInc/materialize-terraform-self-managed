# Workload Identity Federation through a Service Account for GitHub Actions
# https://github.com/google-github-actions/auth?tab=readme-ov-file#workload-identity-federation-through-a-service-account
#
# PREREQUISITES: The user running this Terraform must have the following roles:
# 1. Create Workload Identity Pools:
# gcloud projects add-iam-policy-binding PROJECT_ID \
#   --member="user:YOUR_EMAIL" --role="roles/iam.workloadIdentityPoolAdmin"
# 2. Enable/manage services:
# gcloud projects add-iam-policy-binding PROJECT_ID \
#   --member="user:YOUR_EMAIL" --role="roles/serviceusage.serviceUsageAdmin"
# 3. Create and manage service accounts + IAM policies:
# gcloud projects add-iam-policy-binding PROJECT_ID \
#   --member="user:YOUR_EMAIL" --role="roles/iam.serviceAccountAdmin" 

# Workload Identity Pool
resource "google_iam_workload_identity_pool" "github_actions" {
  project                   = var.project_id
  workload_identity_pool_id = "github-actions-pool"
  display_name              = "GitHub Actions Pool"
  description               = "Workload Identity Pool for GitHub Actions CI/CD"
}

# Workload Identity Provider for GitHub Actions OIDC
resource "google_iam_workload_identity_pool_provider" "github_actions" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_actions.workload_identity_pool_id
  workload_identity_pool_provider_id = "mz-github-actions-provider"
  display_name                       = "GA Materialize Provider"
  description                        = "Materialize OIDC provider for GitHub Actions"

  # Attribute mapping from GitHub OIDC token to GCP attributes
  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
    "attribute.workflow"         = "assertion.workflow"
  }

  # Security: Only allow tokens from MaterializeInc organization
  attribute_condition = "assertion.repository_owner == 'MaterializeInc'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Create a service account for GitHub Actions
resource "google_service_account" "github_actions" {
  project      = var.project_id
  account_id   = "github-actions-materialize"
  display_name = "GitHub Actions Materialize Service Account"
  description  = "Service Account for GitHub Actions CI/CD workflows"
}

# Grant IAM permissions to the Service Account
# GitHub Actions will impersonate this service account
resource "google_project_iam_member" "github_actions_editor" {
  project = var.project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

resource "google_project_iam_member" "github_actions_iam_service_account_admin" {
  project = var.project_id
  role    = "roles/iam.serviceAccountAdmin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

resource "google_project_iam_member" "github_actions_servicenetworking_networks_admin" {
  project = var.project_id
  role    = "roles/servicenetworking.networksAdmin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

resource "google_project_iam_member" "github_actions_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

resource "google_project_iam_member" "github_actions_container_admin" {
  project = var.project_id
  role    = "roles/container.admin"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Allow the Workload Identity Pool to impersonate the Service Account
resource "google_service_account_iam_member" "github_actions_workload_identity_user" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_actions.name}/attribute.repository/${var.github_repository}"
}

# Enable required APIs for the tests
resource "google_project_service" "required_apis" {
  for_each = toset([
    "container.googleapis.com",
    "sqladmin.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "iamcredentials.googleapis.com",
    "iam.googleapis.com",        # Required for roles/iam.serviceAccountAdmin
    "storage.googleapis.com"     # Required for roles/storage.admin
  ])

  project = var.project_id
  service = each.value

  disable_dependent_services = false
}
