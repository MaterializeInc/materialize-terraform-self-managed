#!/bin/sh
# Annotate the VPC CNI resources EKS creates by default so Helm will adopt
# rather than collide with them, and attach the IRSA role to the service
# account.
#
# Invoked by a local-exec provisioner, which runs it through terraform's
# default /bin/sh — dash, or busybox sh in Materialize's BYOC stack-deployer
# image — so this must stay POSIX sh with no bashisms.
#
# Required environment (supplied by the provisioner):
#   KUBECONFIG_DATA, ROLE_ARN
set -eu

kubeconfig_file=$(mktemp)
trap 'rm -f "${kubeconfig_file}"' EXIT
echo "${KUBECONFIG_DATA}" > "${kubeconfig_file}"

helm_annotate() {
  kubectl --kubeconfig "${kubeconfig_file}" annotate "$@" meta.helm.sh/release-name=aws-vpc-cni meta.helm.sh/release-namespace=kube-system --overwrite
  kubectl --kubeconfig "${kubeconfig_file}" label "$@" app.kubernetes.io/managed-by=Helm --overwrite
}

# Namespaced resources
helm_annotate daemonset aws-node -n kube-system
helm_annotate serviceaccount aws-node -n kube-system
helm_annotate configmap amazon-vpc-cni -n kube-system

# Cluster-scoped resources
helm_annotate clusterrole aws-node
helm_annotate clusterrolebinding aws-node

# Add IRSA annotation to service account
kubectl --kubeconfig "${kubeconfig_file}" annotate serviceaccount aws-node -n kube-system \
  eks.amazonaws.com/role-arn="${ROLE_ARN}" --overwrite

echo "VPC CNI resources annotated for Helm adoption."
