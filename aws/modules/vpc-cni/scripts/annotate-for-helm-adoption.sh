#!/bin/sh
# Annotate the VPC CNI resources EKS created on clusters built with EKS module
# v20 and earlier so Helm adopts them instead of colliding (the IRSA annotation
# comes from the chart values). Run by a local-exec via /bin/sh (dash, or busybox
# sh in the BYOC stack-deployer image): POSIX sh only.
#
# Env: KUBECONFIG_DATA
set -eu

kubeconfig_file=$(mktemp)
trap 'rm -f "${kubeconfig_file}"' EXIT
echo "${KUBECONFIG_DATA}" > "${kubeconfig_file}"

# v21+ clusters do not bootstrap the self-managed VPC CNI
# (bootstrap_self_managed_addons = false), so annotate only what exists.
helm_annotate() {
  if ! kubectl --kubeconfig "${kubeconfig_file}" get "$@" >/dev/null 2>&1; then
    echo "Skipping $* (not found; Helm will create it)."
    return 0
  fi
  kubectl --kubeconfig "${kubeconfig_file}" annotate "$@" meta.helm.sh/release-name=aws-vpc-cni meta.helm.sh/release-namespace=kube-system --overwrite
  kubectl --kubeconfig "${kubeconfig_file}" label "$@" app.kubernetes.io/managed-by=Helm --overwrite
}

helm_annotate daemonset aws-node -n kube-system
helm_annotate serviceaccount aws-node -n kube-system
helm_annotate configmap amazon-vpc-cni -n kube-system

helm_annotate clusterrole aws-node
helm_annotate clusterrolebinding aws-node

echo "VPC CNI resources annotated for Helm adoption."
