# RustFS on a dedicated storage node pool, as a persist backend.
#
# Pairs the portable RustFS module with a node pool whose instance store NVMe
# is available as PersistentVolumes, so the store sits on local disk rather
# than EBS.

module "storage_pool" {
  source = "../storage-node-pool"

  name               = var.name
  instance_types     = var.instance_types
  limits             = var.node_limits
  ami_selector_terms = var.ami_selector_terms
  instance_profile   = var.instance_profile
  security_group_ids = var.security_group_ids
  subnet_ids         = var.subnet_ids
  kubeconfig_data    = var.kubeconfig_data
  tags               = var.tags

  volume_group       = var.volume_group
  storage_class_name = var.storage_class_name
  lvm_chart_version  = var.lvm_chart_version
  install_csi_driver = var.install_csi_driver
}

module "rustfs" {
  source = "../../../kubernetes/modules/object-store-rustfs"

  name      = var.name
  namespace = var.namespace
  image     = var.image
  bucket    = var.bucket
  region    = var.region

  # One pod per node, one drive each: the NVMe-bearing instance families carry
  # a single device per node, so erasure coding spreads across nodes rather
  # than across drives.
  replicas           = var.replicas
  drives_per_replica = var.drives_per_replica
  drive_size         = var.drive_size
  storage_class      = module.storage_pool.storage_class_name

  node_selector = module.storage_pool.node_selector
  tolerations   = module.storage_pool.tolerations

  depends_on = [module.storage_pool]
}
