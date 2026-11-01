#!/bin/sh
# Delete ENIs left behind by the VPC CNI when this node group's nodes
# terminated. Invoked by a destroy-time local-exec provisioner, which runs it
# through terraform's default /bin/sh — dash, or busybox sh in Materialize's
# BYOC stack-deployer image — so this must stay POSIX sh with no bashisms.
#
# Only ENIs in "available" status are touched, so ENIs still attached to
# running nodes from other node groups are left alone.
#
# Required environment (supplied by the provisioner):
#   SG_ID, REGION, CLUSTER_NAME, NODE_GROUP_PREFIX
# Optional:
#   PROFILE   AWS profile name; unset or empty uses the default credentials.
set -eu

PROFILE_ARGS=""
if [ -n "${PROFILE:-}" ]; then
  PROFILE_ARGS="--profile ${PROFILE}"
fi

echo "Cleaning up orphaned ENIs for security group $SG_ID in $REGION..."

delete_eni() {
  ENI_ID="$1"
  echo "  Deleting $ENI_ID..."
  # The ENI may have been deleted between the list call and now
  # (e.g. by the VPC CNI). Treat NotFound as success.
  # shellcheck disable=SC2086 # PROFILE_ARGS must word-split into flags
  DELETE_OUTPUT=$(aws ec2 delete-network-interface \
    --network-interface-id "$ENI_ID" \
    --region "$REGION" $PROFILE_ARGS 2>&1) || {
    if echo "$DELETE_OUTPUT" | grep -q "InvalidNetworkInterfaceID.NotFound"; then
      echo "  Already deleted, skipping."
      return 0
    fi
    echo "$DELETE_OUTPUT" >&2
    return 1
  }
}

cleanup_enis() {
  ENI_QUERY="$1"
  shift
  # shellcheck disable=SC2086 # PROFILE_ARGS must word-split into flags
  ENIS=$(aws ec2 describe-network-interfaces \
    --filters \
      "Name=group-id,Values=$SG_ID" \
      "Name=status,Values=available" \
      "$@" \
    --query "$ENI_QUERY" \
    --output text \
    --region "$REGION" $PROFILE_ARGS) || return 1

  PASS_STATUS=0
  for ENI_ID in $ENIS; do
    [ "$ENI_ID" = "None" ] && continue
    delete_eni "$ENI_ID" || PASS_STATUS=1
  done
  return "$PASS_STATUS"
}

# Try every selector, but report failure so Terraform retries the destroy hook.
CLEANUP_STATUS=0

# ENI ownership tag styles:
# - EKS: cluster and node group.
# - CNI: cluster, when the CNI's CLUSTER_NAME is configured.
# - CNI: node instance without a cluster tag.
echo "Cleaning up EKS-tagged ENIs..."
cleanup_enis \
  "NetworkInterfaces[?TagSet[?Key=='eks:nodegroup-name' && starts_with(Value, '$NODE_GROUP_PREFIX')]].NetworkInterfaceId" \
  "Name=tag:eks:cluster-name,Values=$CLUSTER_NAME" || CLEANUP_STATUS=1

echo "Cleaning up VPC CNI cluster-tagged ENIs..."
cleanup_enis "NetworkInterfaces[*].NetworkInterfaceId" \
  "Name=tag:cluster.k8s.amazonaws.com/name,Values=$CLUSTER_NAME" || CLEANUP_STATUS=1

echo "Cleaning up VPC CNI node-tagged ENIs..."
cleanup_enis "NetworkInterfaces[?!(TagSet[?Key=='cluster.k8s.amazonaws.com/name'])].NetworkInterfaceId" \
  "Name=tag-key,Values=node.k8s.amazonaws.com/instance_id" \
  "Name=description,Values=aws-K8S-*" || CLEANUP_STATUS=1

if [ "$CLEANUP_STATUS" -ne 0 ]; then
  exit "$CLEANUP_STATUS"
fi

echo "ENI cleanup complete."
