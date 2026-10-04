#!/bin/sh
# Scale a deployment (the provider's kube-dns or its autoscaler) to zero.
# A missing deployment is success (e.g. EKS v21 module clusters have none).
# Must stay POSIX sh: it runs under dash or busybox sh (BYOC stack-deployer).
#
# Required environment: KUBECONFIG_DATA, DEPLOYMENT_NAME, NAMESPACE
set -eu

kubeconfig_file=$(mktemp)
trap 'rm -f "${kubeconfig_file}"' EXIT
echo "${KUBECONFIG_DATA}" > "${kubeconfig_file}"

# Check with `get --ignore-not-found` rather than parsing `scale` errors, whose
# text varies across kubectl versions. Real failures (API down, expired creds,
# RBAC) still fail through `set -e`.
existing=$(kubectl --kubeconfig="${kubeconfig_file}" get deployment "${DEPLOYMENT_NAME}" \
  -n "${NAMESPACE}" --ignore-not-found -o name)
if [ -z "${existing}" ]; then
  echo "Deployment ${DEPLOYMENT_NAME} not found, skipping"
  exit 0
fi

kubectl --kubeconfig="${kubeconfig_file}" scale deployment "${DEPLOYMENT_NAME}" \
  -n "${NAMESPACE}" --replicas=0
echo "Successfully scaled down ${DEPLOYMENT_NAME} to 0 replicas"
