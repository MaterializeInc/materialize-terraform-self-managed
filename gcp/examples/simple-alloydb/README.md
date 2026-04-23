# Simple AlloyDB Example

This example deploys Materialize on GCP using AlloyDB for metadata storage.

## GCP Prerequisites

### Required APIs

Enable the following APIs on your GCP project:

```bash
PROJECT_ID="your-project-id"

gcloud services enable alloydb.googleapis.com --project=$PROJECT_ID
gcloud services enable container.googleapis.com --project=$PROJECT_ID
gcloud services enable storage.googleapis.com --project=$PROJECT_ID
gcloud services enable servicenetworking.googleapis.com --project=$PROJECT_ID
gcloud services enable compute.googleapis.com --project=$PROJECT_ID
gcloud services enable iam.googleapis.com --project=$PROJECT_ID
gcloud services enable cloudresourcemanager.googleapis.com --project=$PROJECT_ID
```

### Required IAM Roles

Your user account needs the following roles on the project:

| Role | Purpose |
|------|---------|
| `roles/alloydb.admin` | Create and manage AlloyDB clusters |
| `roles/container.admin` | Create and manage GKE clusters |
| `roles/compute.networkAdmin` | Create VPC networks and subnets |
| `roles/storage.admin` | Create GCS buckets |
| `roles/iam.serviceAccountAdmin` | Create and manage service accounts |
| `roles/iam.serviceAccountUser` | Use service accounts for GKE nodes |
| `roles/serviceusage.serviceUsageConsumer` | Use APIs with quota project |

Grant these roles (requires project admin):

```bash
PROJECT_ID="your-project-id"
USER_EMAIL="your-email@example.com"

# Option 1: Grant editor role (simpler)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="user:$USER_EMAIL" \
  --role="roles/editor"

# Option 2: Grant specific roles
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="user:$USER_EMAIL" \
  --role="roles/alloydb.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="user:$USER_EMAIL" \
  --role="roles/container.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="user:$USER_EMAIL" \
  --role="roles/compute.networkAdmin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="user:$USER_EMAIL" \
  --role="roles/storage.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="user:$USER_EMAIL" \
  --role="roles/iam.serviceAccountAdmin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="user:$USER_EMAIL" \
  --role="roles/iam.serviceAccountUser"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="user:$USER_EMAIL" \
  --role="roles/serviceusage.serviceUsageConsumer"
```

## Usage

1. Create a `terraform.tfvars` file with your project settings
2. Run `terraform init && terraform apply`
