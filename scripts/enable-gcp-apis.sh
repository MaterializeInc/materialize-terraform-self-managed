#!/usr/bin/env bash
# Enable the Google Cloud APIs the Materialize GCP modules depend on.
#
#     scripts/enable-gcp-apis.sh my-project-id
#
# Safe to re-run: enabling an API that is already enabled is a no-op. Enabling
# an API can take a minute or two to propagate, so if a terraform apply run
# immediately afterwards reports a service as disabled, wait and re-run it.
#
# This list is the companion to the "Required Permissions" section in
# gcp/README.md: the APIs decide what exists in the project, the roles decide
# whether you are allowed to create it.

set -euo pipefail

project="${1:-}"
if [[ -z "$project" ]]; then
  echo "usage: $(basename "$0") <project-id>" >&2
  exit 1
fi

# Keep in sync with the resources under gcp/modules/. Each entry notes what
# needs it, so an unused one is easy to spot if a module ever drops a resource.
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
