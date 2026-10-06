#!/bin/sh
# Delete the nodeclaims belonging to a Karpenter nodepool. Terraform does not
# know about the EC2 instances Karpenter spawned, so without this they leak
# when the nodepool goes away.
#
# The nodeclaims carry a finalizer that holds them until the backing EC2
# instance is gone, hence --wait=true. The wait is bounded: Karpenter only
# terminates the instance once the node has drained and its volumes have
# detached, so anything that prevents either (a VolumeAttachment whose CSI
# driver is already gone, a pod that cannot be evicted) would otherwise hold
# `terraform destroy` silently for as long as anyone lets it run. On timeout
# this names what each remaining nodeclaim is waiting on and fails.
#
# Invoked by a destroy-time local-exec provisioner, which runs it through
# terraform's default /bin/sh — dash, or busybox sh in Materialize's BYOC
# stack-deployer image — so this must stay POSIX sh with no bashisms.
#
# Required environment (supplied by the provisioner):
#   NODEPOOL_NAME, KUBECONFIG_DATA, DELETE_TIMEOUT
set -eu

if [ -z "${KUBECONFIG_DATA}" ]; then
  echo "Error: KUBECONFIG_DATA is empty"
  exit 1
fi

kubeconfig_file=$(mktemp)
trap 'rm -f "${kubeconfig_file}"' EXIT
echo "${KUBECONFIG_DATA}" > "${kubeconfig_file}"

k() {
  kubectl --kubeconfig "${kubeconfig_file}" "$@"
}

selector="karpenter.sh/nodepool=${NODEPOOL_NAME}"

nodeclaims=$(k get nodeclaims -l "${selector}" -o name)
[ -z "${nodeclaims}" ] && exit 0

if echo "${nodeclaims}" | xargs kubectl --kubeconfig "${kubeconfig_file}" delete --wait=true --timeout="${DELETE_TIMEOUT}"; then
  exit 0
fi

echo "Error: nodeclaims of nodepool ${NODEPOOL_NAME} still exist after ${DELETE_TIMEOUT}." >&2
echo "Karpenter holds each one until its node has drained, its volumes have detached, and its instance is terminated. Still in the way:" >&2
# Best effort from here: a nodeclaim can finish going away between the list
# and the lookup, and that must not cut the report short.
for nodeclaim in $(k get nodeclaims -l "${selector}" -o name || true); do
  node=$(k get "${nodeclaim}" -o jsonpath='{.status.nodeName}' || true)
  finalizers=$(k get "${nodeclaim}" -o jsonpath='{.metadata.finalizers}' || true)
  echo "  ${nodeclaim} (node ${node:-<none>}, finalizers ${finalizers:-<none>})" >&2
  [ -z "${node}" ] && continue
  k get volumeattachments --no-headers \
    -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,ATTACHER:.spec.attacher \
    | awk -v n="${node}" '$2 == n { print "    volumeattachment/" $1 " (attacher " $3 ")" }' >&2
  # A drain never evicts DaemonSet pods or static mirror pods (owned by the
  # Node), so they cannot be what blocks it and are left out.
  k get pods --all-namespaces --no-headers --field-selector "spec.nodeName=${node}" \
    -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,OWNER:.metadata.ownerReferences[0].kind \
    | awk '$3 != "DaemonSet" && $3 != "Node" { print "    pod/" $2 " (namespace " $1 ")" }' >&2
done
echo "Release whatever is listed and run destroy again." >&2
exit 1
