#!/bin/sh
# Annotate the VPC CNI resources EKS created by default on clusters built
# with EKS module v20 and earlier, so Helm will adopt rather than collide
# with them. The IRSA role annotation on the service account is managed by
# the Helm chart values.
#
# Invoked by a local-exec provisioner, which runs it through terraform's
# default /bin/sh — dash, or busybox sh in Materialize's BYOC stack-deployer
# image — so this must stay POSIX sh with no bashisms.
#
# Required environment (supplied by the provisioner):
#   KUBECONFIG_DATA
set -eu

kubeconfig_file=$(mktemp)
trap 'rm -f "${kubeconfig_file}"' EXIT
echo "${KUBECONFIG_DATA}" > "${kubeconfig_file}"

# Clusters created with EKS module v21+ no longer bootstrap the self-managed
# VPC CNI (bootstrap_self_managed_addons is false), so on a fresh cluster
# there is nothing to adopt and Helm installs everything itself. Annotate
# only the resources that actually exist.
helm_annotate() {
  if ! kubectl --kubeconfig "${kubeconfig_file}" get "$@" >/dev/null 2>&1; then
    echo "Skipping $* (not found; Helm will create it)."
    return 0
  fi
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

echo "VPC CNI resources annotated for Helm adoption."
