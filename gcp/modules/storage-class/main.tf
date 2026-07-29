# GCP Persistent Disk Storage Class for Kubernetes
#
# This module creates a Kubernetes StorageClass optimized for GCP zonal
# Persistent Disks in multi-zone GKE clusters.
#
# Why WaitForFirstConsumer?
# -------------------------
# GCP Persistent Disks (PDs) are zonal resources - they exist in a single zone
# and can only be attached to nodes in that same zone. In a multi-zone GKE
# cluster, using the default "Immediate" volume binding mode would create the PD
# in an arbitrary zone before knowing where the pod will be scheduled. This can
# cause scheduling failures if the pod gets scheduled to a different zone.
#
# Using "WaitForFirstConsumer" delays PD creation until a pod using the PVC is
# scheduled. The CSI driver then creates the PD in the same zone as the node,
# ensuring the volume is always accessible to the pod.
#
# This is especially important for StatefulSets and pods with persistent storage
# in multi-zone deployments.

resource "kubernetes_storage_class" "pd_ssd" {
  count = var.create_storage_class ? 1 : 0

  metadata {
    name = var.storage_class_name
    annotations = var.set_as_default ? {
      "storageclass.kubernetes.io/is-default-class" = "true"
    } : {}
  }

  storage_provisioner    = "pd.csi.storage.gke.io"
  reclaim_policy         = var.reclaim_policy
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = var.allow_volume_expansion

  parameters = merge(
    {
      type = var.disk_type
    },
    var.replication_type != null ? { "replication-type" = var.replication_type } : {}
  )
}
