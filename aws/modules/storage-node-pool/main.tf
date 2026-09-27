# A node pool whose instance store NVMe is available to workloads as
# PersistentVolumes.
#
# Three pieces have to agree for that to happen, and getting any one of them
# wrong falls back to EBS without failing, which measures the network instead
# of the disk:
#
#   node class   ephemeral_storage_mode = "lvm" runs ephemeral-storage-setup,
#                which combines the NVMe into a volume group
#   node pool    NVMe-bearing instance types, labelled and tainted so only the
#                workload that asked for them lands there
#   CSI driver   provisions logical volumes from that group
#
# They are wired together here so a caller gets a StorageClass and the
# selector/tolerations to reach it, rather than having to assemble them.

locals {
  node_label_key = "materialize.cloud/storage-pool"

  # Marks every pool built by this module, whatever its name. The CSI driver is
  # cluster-scoped and selects on this, so one install serves every pool; the
  # per-pool label below is what a workload uses to pick its own nodes.
  shared_label_key = "materialize.cloud/local-nvme"

  node_labels = {
    (local.node_label_key)   = var.name
    (local.shared_label_key) = "true"
  }

  csi_node_selector = {
    (local.shared_label_key) = "true"
  }

  # Keeps everything else off these nodes. Whatever uses the pool tolerates it.
  node_taints = [
    {
      key    = local.node_label_key
      value  = var.name
      effect = "NoSchedule"
    }
  ]

  tolerations = [
    {
      key      = local.node_label_key
      operator = "Equal"
      value    = var.name
      effect   = "NoSchedule"
    }
  ]
}

module "node_class" {
  source = "../karpenter-ec2nodeclass"

  name               = var.name
  ami_selector_terms = var.ami_selector_terms
  instance_types     = var.instance_types
  instance_profile   = var.instance_profile
  security_group_ids = var.security_group_ids
  subnet_ids         = var.subnet_ids
  tags               = var.tags

  # These nodes host a store rather than Materialize, so they have nothing to
  # spill and no use for swap. The instance store becomes a volume group.
  ephemeral_storage_mode    = "lvm"
  ephemeral_storage_vg_name = var.volume_group
}

module "node_pool" {
  source = "../karpenter-nodepool"

  name           = var.name
  nodeclass_name = var.name
  instance_types = var.instance_types
  node_labels    = local.node_labels
  node_taints    = local.node_taints
  limits         = var.limits

  kubeconfig_data = var.kubeconfig_data

  depends_on = [module.node_class]
}

# Cluster-scoped, so only one pool installs it. A second pool on the same
# cluster sets `install_csi_driver = false` and shares this one, which works
# because the driver selects on the shared label rather than a pool's own.
module "storage_class" {
  count  = var.install_csi_driver ? 1 : 0
  source = "../../../kubernetes/modules/lvm-local-storage"

  storage_class_name = var.storage_class_name
  volume_group       = var.volume_group
  chart_version      = var.lvm_chart_version

  # The node plugin has work to do on every pool's nodes, and each pool taints
  # its own, so it tolerates any taint rather than one pool's.
  node_selector = local.csi_node_selector
  tolerations = [
    {
      key      = local.node_label_key
      operator = "Exists"
      effect   = "NoSchedule"
    }
  ]

  depends_on = [module.node_pool]
}
