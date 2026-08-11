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

# Clean up orphaned ENIs associated with this node group's security group.
#
# When the node group is destroyed, the VPC CNI plugin on terminating nodes
# may not clean up ENIs it created. These ENIs remain associated with the
# node security group, preventing Terraform from deleting it.
#
# The node group depends_on this resource, so during destroy the node group
# is deleted first, then this cleanup runs, then the security group (in the
# parent EKS module) can be deleted cleanly.
#
# Only ENIs in "available" status (not attached to any instance) are cleaned
# up, so ENIs belonging to still-running nodes from other node groups are
# left untouched.
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

  # Passed through from the caller so they are known at plan time. When a
  # caller puts a depends_on on this module call, Terraform defers every data
  # source inside it (and inside the upstream module) to apply time. The
  # upstream module resolves these from data sources gated by a conditional
  # count when they are not supplied, so leaving them unset then fails the
  # plan with "Invalid count argument" — and even when it can plan, the IAM
  # policy ARNs derived from them become unknown, forcing a
  # destroy-and-recreate of every aws_iam_role_policy_attachment whose
  # create-before-destroy replacement detaches the policy from the live role.
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

  # v21 of the upstream module requires a map; key each entry by taint
  # key and effect to preserve the list-based interface of this module.
  # Kubernetes allows the same taint key with different effects, so the
  # key alone would collide.
  taints = { for t in var.node_taints : "${t.key}:${t.effect}" => t }

  # useful to disable this when prefix might be too long and hit following char limit
  # expected length of name_prefix to be in the range (1 - 38)
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
