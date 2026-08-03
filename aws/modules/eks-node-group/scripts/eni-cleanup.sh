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

# ENIs come in two tag styles:
# 1. EKS-managed: eks:cluster-name + eks:nodegroup-name
# 2. VPC CNI-managed: cluster.k8s.amazonaws.com/name
echo "Cleaning up EKS-tagged ENIs..."
# shellcheck disable=SC2086 # PROFILE_ARGS must word-split into flags
EKS_ENIS=$(aws ec2 describe-network-interfaces \
  --filters \
    "Name=group-id,Values=$SG_ID" \
    "Name=status,Values=available" \
    "Name=tag:eks:cluster-name,Values=$CLUSTER_NAME" \
  --query "NetworkInterfaces[?TagSet[?Key=='eks:nodegroup-name' && starts_with(Value, '$NODE_GROUP_PREFIX')]].NetworkInterfaceId" \
  --output text \
  --region "$REGION" $PROFILE_ARGS)

for ENI_ID in $EKS_ENIS; do
  [ "$ENI_ID" = "None" ] && continue
  delete_eni "$ENI_ID"
done

echo "Cleaning up VPC CNI-tagged ENIs..."
# shellcheck disable=SC2086 # PROFILE_ARGS must word-split into flags
CNI_ENIS=$(aws ec2 describe-network-interfaces \
  --filters \
    "Name=group-id,Values=$SG_ID" \
    "Name=status,Values=available" \
    "Name=tag:cluster.k8s.amazonaws.com/name,Values=$CLUSTER_NAME" \
  --query "NetworkInterfaces[*].NetworkInterfaceId" \
  --output text \
  --region "$REGION" $PROFILE_ARGS)

for ENI_ID in $CNI_ENIS; do
  [ "$ENI_ID" = "None" ] && continue
  delete_eni "$ENI_ID"
done

echo "ENI cleanup complete."
