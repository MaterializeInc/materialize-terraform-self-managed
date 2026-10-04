locals {
  node_labels = merge(
    var.labels,
    var.swap_enabled ? {
      "materialize.cloud/swap"                 = "true"
      "materialize.cloud/disk-config-required" = "true"
    } : {}
  )

  swap_bootstrap_args = <<-EOF
    [settings.bootstrap-containers.diskstrap]
    source = "${var.disk_setup_image}"
    mode = "always"
    essential = true
    user-data = "${base64encode(jsonencode(["swap", "--cloud-provider", "aws", "--bottlerocket-enable-swap"]))}"

    [settings.kernel.sysctl]
    "vm.swappiness" = "100"
    "vm.min_free_kbytes" = "1048576"
    "vm.watermark_scale_factor" = "100"
  EOF
}

# On destroy, delete ENIs the VPC CNI left on the node security group, which
# would block deleting it. The node group depends on this, so it runs after the
# node group is gone. Only detached ("available") ENIs are removed.
resource "terraform_data" "eni_cleanup" {
  triggers_replace = {
    security_group_id = var.cluster_primary_security_group_id
    cluster_name      = var.cluster_name
    node_group_name   = var.node_group_name
    region            = var.aws_region
    profile           = var.aws_profile
  }

  provisioner "local-exec" {
    when = destroy
    environment = {
      SG_ID             = self.triggers_replace.security_group_id
      CLUSTER_NAME      = self.triggers_replace.cluster_name
      NODE_GROUP_PREFIX = self.triggers_replace.node_group_name
      REGION            = self.triggers_replace.region
      PROFILE           = self.triggers_replace.profile
    }
    command = "sh '${path.module}/scripts/eni-cleanup.sh'"
  }
}

module "node_group" {
  source  = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "~> 21.0"

  # Must be known at plan time. With a depends_on on this module, the upstream
  # data sources that would look these up defer to apply, which fails with
  # "Invalid count argument" or replaces (and detaches) every policy attachment.
  partition  = var.partition
  account_id = var.account_id

  cluster_name   = var.cluster_name
  subnet_ids     = var.subnet_ids
  name           = var.node_group_name
  desired_size   = var.desired_size
  min_size       = var.min_size
  max_size       = var.max_size
  instance_types = var.instance_types
  capacity_type  = var.capacity_type
  ami_type       = var.ami_type
  labels         = local.node_labels

  # Upstream v21 takes a map. Key by key and effect, since one taint key can
  # appear with several effects.
  taints = { for t in var.node_taints : "${t.key}:${t.effect}" => t }

  # Disable if the name is too long: name_prefix allows at most 38 characters.
  iam_role_use_name_prefix = var.iam_role_use_name_prefix

  iam_role_permissions_boundary = var.iam_permissions_boundary

  launch_template_name = var.launch_template_name

  # v21 changed these defaults in ways that would produce a launch template
  # diff and roll every existing node group; pin the v20 defaults instead.
  use_latest_ami_release_version = false
  enable_monitoring              = true
  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  bootstrap_extra_args = var.swap_enabled ? local.swap_bootstrap_args : ""

  cluster_service_cidr              = var.cluster_service_cidr
  cluster_primary_security_group_id = var.cluster_primary_security_group_id

  tags = var.tags

  depends_on = [terraform_data.eni_cleanup]
}
