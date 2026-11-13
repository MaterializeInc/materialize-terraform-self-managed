locals {
  # Same shape as var.lifecycle_rules so concat yields one object type.
  # Not gated on versioning: disabling it leaves existing noncurrent versions.
  version_ttl = var.version_ttl != null ? [{
    action = {
      type          = "Delete"
      storage_class = null
    }
    condition = {
      age                        = null
      created_before             = null
      with_state                 = null
      num_newer_versions         = null
      days_since_noncurrent_time = var.version_ttl
    }
  }] : []

  lifecycle_rules = concat(var.lifecycle_rules, local.version_ttl)

}

resource "google_storage_bucket" "materialize" {
  name          = "${var.prefix}-storage-${var.project_id}"
  location      = var.region
  project       = var.project_id
  force_destroy = true

  uniform_bucket_level_access = true

  versioning {
    enabled = var.versioning
  }

  dynamic "lifecycle_rule" {
    for_each = local.lifecycle_rules
    content {
      action {
        type          = lifecycle_rule.value.action.type
        storage_class = lifecycle_rule.value.action.storage_class
      }
      condition {
        age                        = lifecycle_rule.value.condition.age
        created_before             = lifecycle_rule.value.condition.created_before
        with_state                 = lifecycle_rule.value.condition.with_state
        num_newer_versions         = lifecycle_rule.value.condition.num_newer_versions
        days_since_noncurrent_time = lifecycle_rule.value.condition.days_since_noncurrent_time
      }
    }
  }


  labels = var.labels
}

resource "google_storage_bucket_iam_member" "materialize_storage" {
  count = var.service_account != null ? 1 : 0

  bucket = google_storage_bucket.materialize.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${var.service_account}"
}

moved {
  from = google_storage_bucket_iam_member.materialize_storage
  to   = google_storage_bucket_iam_member.materialize_storage[0]
}

# Only for an S3-compatible persist URL. A recreated key has a new secret, so
# the moved block keeps the existing one in place.
resource "google_storage_hmac_key" "materialize" {
  count = var.create_hmac_key ? 1 : 0

  project               = var.project_id
  service_account_email = var.service_account
}

moved {
  from = google_storage_hmac_key.materialize
  to   = google_storage_hmac_key.materialize[0]
}

# Native access (gcs://) through GKE Workload Identity. A dedicated service
# account rather than a member added to the gke module's: that module binds
# roles/iam.workloadIdentityUser on its own account authoritatively, so another
# member there would be removed on its next apply.
resource "google_service_account" "persist" {
  count = var.workload_identity != null ? 1 : 0

  project      = var.project_id
  account_id   = "${var.prefix}-persist"
  display_name = "Materialize persist (${var.prefix})"

  lifecycle {
    precondition {
      condition     = length("${var.prefix}-persist") <= 30
      error_message = "The persist service account ID \"${var.prefix}-persist\" exceeds GCP's 30-character limit; shorten prefix to 22 characters or fewer."
    }
  }
}

resource "google_storage_bucket_iam_member" "persist" {
  count = var.workload_identity != null ? 1 : 0

  bucket = google_storage_bucket.materialize.name
  role   = "roles/storage.objectAdmin"
  member = google_service_account.persist[0].member
}

resource "google_service_account_iam_member" "persist_workload_identity" {
  count = var.workload_identity != null ? 1 : 0

  service_account_id = google_service_account.persist[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.workload_identity.namespace}/${var.workload_identity.service_account_name}]"
}
