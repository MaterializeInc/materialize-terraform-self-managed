#!/bin/sh
# Scale a deployment to zero replicas. Used to stand down the cloud provider's
# default kube-dns deployment and its autoscaler so only the custom CoreDNS in
# this module serves DNS.
#
# A missing deployment is treated as success: the provider may not have created
# it (EKS clusters built with the v21 module bootstrap no CoreDNS at all), or an
# operator may have removed it already. Absence is established with an explicit
# `get --ignore-not-found` rather than by matching the text `scale` prints when
# the deployment is missing, which differs across kubectl versions: 1.34 says
# "no objects passed to scale", while the version on CI says "Error from server
# (NotFound)".
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

# `--ignore-not-found` exits 0 with empty output when the deployment is absent,
# so a genuine failure — unreachable API server, expired credentials, missing
# RBAC — still fails the script through `set -e` rather than being mistaken for
# absence and silently skipped.
existing=$(kubectl --kubeconfig="${kubeconfig_file}" get deployment "${DEPLOYMENT_NAME}" \
  -n "${NAMESPACE}" --ignore-not-found -o name)
if [ -z "${existing}" ]; then
  echo "Deployment ${DEPLOYMENT_NAME} not found, skipping"
  exit 0
fi

kubectl --kubeconfig="${kubeconfig_file}" scale deployment "${DEPLOYMENT_NAME}" \
  -n "${NAMESPACE}" --replicas=0
echo "Successfully scaled down ${DEPLOYMENT_NAME} to 0 replicas"
