#!/usr/bin/env bash
# Enable the Google Cloud APIs the Materialize GCP modules depend on.
#
#     scripts/enable-gcp-apis.sh my-project-id
#
# Safe to re-run. Enabling can take a minute or two to propagate, so if
# terraform apply then reports a service as disabled, wait and re-run it.
#
# Companion to the "Required Permissions" section in gcp/README.md.

set -euo pipefail

project="${1:-}"
if [[ -z "$project" ]]; then
  echo "usage: $(basename "$0") <project-id>" >&2
  exit 1
fi

# Keep in sync with gcp/modules/ and the list in gcp/examples/simple/README.md.
apis=(
  cloudresourcemanager.googleapis.com # Project metadata and IAM bindings
  compute.googleapis.com              # VPC, subnets, Cloud NAT, firewalls, GKE nodes
  container.googleapis.com            # GKE cluster and node pools
  iam.googleapis.com                  # Service accounts and Workload Identity
  iamcredentials.googleapis.com       # Short-lived credentials for Workload Identity
  pubsub.googleapis.com               # GKE upgrade notifications (on by default)
  servicenetworking.googleapis.com    # Private services access for Cloud SQL
  serviceusage.googleapis.com         # Required in order to enable any of the above
  sqladmin.googleapis.com             # Cloud SQL for PostgreSQL
  storage.googleapis.com              # Cloud Storage buckets and HMAC keys
)

echo "Enabling ${#apis[@]} APIs on ${project}..."
gcloud services enable "${apis[@]}" --project="${project}"
echo "Done. If a subsequent terraform apply reports a service as disabled,"
echo "give the change a minute to propagate and re-run it."
