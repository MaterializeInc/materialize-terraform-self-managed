#!/bin/sh
# Wait until the EBS CSI driver has finished the work it still owes before it
# is uninstalled: no VolumeAttachment left for its attacher, and no Released
# PersistentVolume left for its provisioner to delete.
#
# Run from the destroy-time provisioner on terraform_data.volume_drain, which
# the module orders after every consumer of its storage class and before the
# driver itself. `helm uninstall` of a consumer returns once its pods are gone,
# but detaching their volumes and deleting the Released ones is work the
# driver does afterwards. Uninstalling the driver first leaves each remaining
# VolumeAttachment with a finalizer nothing can clear, Karpenter then never
# terminates the node it is attached to, and that node pool's destroy hangs.
#
# Bound PersistentVolumes are deliberately not waited on. They belong to a
# claim that still exists, such as one a StatefulSet's volumeClaimTemplates
# created and `helm uninstall` leaves behind by design, and the driver will
# not delete them however long it is given.
#
# Fails on timeout rather than proceeding, naming what is still held, since
# proceeding is what produces the hang.
#
# Invoked by a destroy-time local-exec provisioner, which runs it through
# terraform's default /bin/sh, so this must stay POSIX sh with no bashisms.
#
# Required environment (supplied by the provisioner):
#   KUBECONFIG_DATA, TIMEOUT_SECONDS
set -eu

if [ -z "${KUBECONFIG_DATA}" ]; then
  echo "Error: KUBECONFIG_DATA is empty" >&2
  exit 1
fi

kubeconfig_file=$(mktemp)
trap 'rm -f "${kubeconfig_file}"' EXIT
echo "${KUBECONFIG_DATA}" > "${kubeconfig_file}"

driver=ebs.csi.aws.com
timeout=${TIMEOUT_SECONDS}
interval=10

# custom-columns prints <none> for a missing field, so objects without the
# field fall out of the awk match instead of erroring.
held() {
  kubectl --kubeconfig "${kubeconfig_file}" get volumeattachments --no-headers \
    -o custom-columns=NAME:.metadata.name,ATTACHER:.spec.attacher,NODE:.spec.nodeName \
    | awk -v d="${driver}" '$2 == d { print "volumeattachment/" $1 " (node " $3 ")" }'
  kubectl --kubeconfig "${kubeconfig_file}" get pv --no-headers \
    -o custom-columns=NAME:.metadata.name,DRIVER:.spec.csi.driver,PHASE:.status.phase \
    | awk -v d="${driver}" '$2 == d && $3 == "Released" { print "pv/" $1 " (Released)" }'
}

elapsed=0
while :; do
  left=$(held)
  [ -z "${left}" ] && exit 0
  if [ "${elapsed}" -ge "${timeout}" ]; then
    echo "Error: ${driver} still holds volumes after ${timeout}s, and uninstalling it now would strand them:" >&2
    echo "${left}" | sed 's/^/  /' >&2
    echo "Remove whatever still uses them, or detach them by hand, then run destroy again." >&2
    exit 1
  fi
  echo "waiting for ${driver} to release: $(echo "${left}" | tr '\n' ' ')"
  sleep "${interval}"
  elapsed=$((elapsed + interval))
done
