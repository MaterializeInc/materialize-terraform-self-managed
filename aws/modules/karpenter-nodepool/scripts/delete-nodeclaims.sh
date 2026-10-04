#!/bin/sh
# Delete a nodepool's nodeclaims so the EC2 instances Karpenter launched, which
# Terraform does not know about, do not leak. A finalizer holds each nodeclaim
# until its instance is gone, hence --wait=true. Run by a destroy-time local-exec
# via /bin/sh (dash, or busybox sh in the BYOC stack-deployer image): POSIX sh only.
#
# Env: NODEPOOL_NAME, KUBECONFIG_DATA
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
