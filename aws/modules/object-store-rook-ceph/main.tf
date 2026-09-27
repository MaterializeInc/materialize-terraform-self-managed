# Ceph on a dedicated storage node pool, as a persist backend.
#
# Pairs the portable Rook module with a node pool whose instance store NVMe is
# available as PersistentVolumes. OSDs come from that StorageClass rather than
# from raw devices, because the node class has already claimed the devices into
# a volume group.

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

module "ceph" {
  source = "../../../kubernetes/modules/object-store-rook-ceph"

  name   = var.name
  bucket = var.bucket
  region = var.region

  osd_storage_class = module.storage_pool.storage_class_name
  osd_count         = var.osd_count
  osd_size          = var.osd_size
  replica_size      = var.replica_size
  mon_count         = var.mon_count
  gateway_instances = var.gateway_instances

  # One OSD per node, so a host is the right unit of failure.
  failure_domain = "host"

  rgw_chunk_size_bytes = var.rgw_chunk_size_bytes
  data_dir_host_path   = var.data_dir_host_path

  node_selector = module.storage_pool.node_selector
  tolerations   = module.storage_pool.tolerations

  depends_on = [module.storage_pool]
}
