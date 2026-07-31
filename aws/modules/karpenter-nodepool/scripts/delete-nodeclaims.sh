#!/bin/sh
# Delete the nodeclaims belonging to a Karpenter nodepool. Terraform does not
# know about the EC2 instances Karpenter spawned, so without this they leak
# when the nodepool goes away.
#
# The nodeclaims carry a finalizer that holds them until the backing EC2
# instance is gone, hence --wait=true.
#
# Invoked by a destroy-time local-exec provisioner, which runs it through
# terraform's default /bin/sh — dash, or busybox sh in Materialize's BYOC
# stack-deployer image — so this must stay POSIX sh with no bashisms.
#
# Required environment (supplied by the provisioner):
#   NODEPOOL_NAME, KUBECONFIG_DATA
set -eu

if [ -z "${KUBECONFIG_DATA}" ]; then
  echo "Error: KUBECONFIG_DATA is empty"
  exit 1
fi

kubeconfig_file=$(mktemp)
trap 'rm -f "${kubeconfig_file}"' EXIT
echo "${KUBECONFIG_DATA}" > "${kubeconfig_file}"

nodeclaims=$(kubectl --kubeconfig "${kubeconfig_file}" get nodeclaims -l "karpenter.sh/nodepool=${NODEPOOL_NAME}" -o name)
if [ -n "${nodeclaims}" ]; then
  echo "${nodeclaims}" | xargs kubectl --kubeconfig "${kubeconfig_file}" delete --wait=true
fi
