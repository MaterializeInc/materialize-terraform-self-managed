#!/bin/sh
# Scale a deployment to zero replicas. Used to stand down the cloud provider's
# default kube-dns deployment and its autoscaler so only the custom CoreDNS in
# this module serves DNS.
#
# A missing deployment is treated as success: the provider may not have created
# it, or an operator may have removed it already.
#
# Invoked by a local-exec provisioner, which runs it through terraform's
# default /bin/sh — dash, or busybox sh in Materialize's BYOC stack-deployer
# image — so this must stay POSIX sh with no bashisms.
#
# Required environment (supplied by the provisioner):
#   KUBECONFIG_DATA, DEPLOYMENT_NAME, NAMESPACE
set -eu

kubeconfig_file=$(mktemp)
trap 'rm -f "${kubeconfig_file}"' EXIT
echo "${KUBECONFIG_DATA}" > "${kubeconfig_file}"

output=$(kubectl --kubeconfig="${kubeconfig_file}" scale deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" --replicas=0 2>&1) || {
  if echo "$output" | grep -q "no objects passed to scale"; then
    echo "Deployment ${DEPLOYMENT_NAME} not found, skipping"
    exit 0
  fi
  echo "Error scaling down ${DEPLOYMENT_NAME} deployment: $output"
  exit 1
}
echo "Successfully scaled down ${DEPLOYMENT_NAME} to 0 replicas"
