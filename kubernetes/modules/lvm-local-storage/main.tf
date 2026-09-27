# PersistentVolumes carved out of the instance store NVMe.
#
# The node class runs `ephemeral-storage-setup lvm`, which combines a node's
# local NVMe into one volume group. This module installs the CSI driver that
# provisions logical volumes from that group, so workloads get ordinary PVCs
# backed by local disk rather than by EBS.
#
# The volumes are as ephemeral as the instances: a logical volume lives on one
# node's instance store and does not survive that node going away. Suitable for
# a store that replicates or erasure-codes across nodes, and for benchmark data.
# Not suitable for anything that expects a volume to outlive its node.

locals {
  namespace = var.create_namespace ? kubernetes_namespace.this[0].metadata[0].name : var.namespace

  labels = {
    "app.kubernetes.io/name"       = "lvm-localpv"
    "app.kubernetes.io/component"  = "storage"
    "app.kubernetes.io/managed-by" = "terraform"
  }
}

resource "kubernetes_namespace" "this" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name   = var.namespace
    labels = local.labels
  }
}

resource "helm_release" "lvm_localpv" {
  name       = "lvm-localpv"
  namespace  = local.namespace
  repository = "https://openebs.github.io/lvm-localpv"
  chart      = "lvm-localpv"
  version    = var.chart_version
  timeout    = var.install_timeout

  # The controller schedules volumes; only the node plugin needs to run where
  # the volume group is, so the selector and tolerations apply to it.
  dynamic "set" {
    for_each = var.node_selector
    content {
      name = "lvmNode.nodeSelector.${replace(set.key, ".", "\\.")}"
      # Helm infers types, so a label value of "true" or a bare number would
      # reach the API server as a bool or an int. Node selector values are
      # strings, and the request is rejected outright if they are not.
      type  = "string"
      value = set.value
    }
  }

  dynamic "set" {
    for_each = length(var.tolerations) > 0 ? range(length(var.tolerations)) : []
    content {
      name  = "lvmNode.tolerations[${set.value}].key"
      value = var.tolerations[set.value].key
    }
  }

  dynamic "set" {
    for_each = length(var.tolerations) > 0 ? range(length(var.tolerations)) : []
    content {
      name  = "lvmNode.tolerations[${set.value}].operator"
      value = var.tolerations[set.value].operator
    }
  }

  dynamic "set" {
    for_each = length(var.tolerations) > 0 ? [
      for i, toleration in var.tolerations : i
      if toleration.value != null
    ] : []
    content {
      name  = "lvmNode.tolerations[${set.value}].value"
      value = var.tolerations[set.value].value
    }
  }

  dynamic "set" {
    for_each = length(var.tolerations) > 0 ? range(length(var.tolerations)) : []
    content {
      name  = "lvmNode.tolerations[${set.value}].effect"
      value = var.tolerations[set.value].effect
    }
  }

  depends_on = [kubernetes_namespace.this]
}

resource "kubernetes_storage_class" "instance_store" {
  metadata {
    name = var.storage_class_name
    annotations = var.is_default_class ? {
      "storageclass.kubernetes.io/is-default-class" = "true"
    } : {}
    labels = local.labels
  }

  storage_provisioner = "local.csi.openebs.io"
  reclaim_policy      = "Delete"

  # A logical volume only exists on the node holding the volume group, so the
  # volume cannot be created until the scheduler has picked a node for the pod.
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    "storage"  = "lvm"
    "volgroup" = var.volume_group
    "fsType"   = var.fs_type
  }

  depends_on = [helm_release.lvm_localpv]
}
