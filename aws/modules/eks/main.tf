module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name = "${var.name_prefix}-eks"

  kubernetes_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.k8s_apiserver_authorized_networks
  endpoint_private_access      = true

  enabled_log_types = var.cluster_enabled_log_types

  # v21 no longer bootstraps kube-proxy and nothing else of ours installs it
  # (unlike the VPC CNI and CoreDNS), so run it as an EKS addon. OVERWRITE
  # adopts the self-managed kube-proxy on older clusters.
  addons = {
    kube-proxy = {
      resolve_conflicts_on_create = "OVERWRITE"
    }
  }

  node_security_group_additional_rules = {
    mz_ingress_http = {
      description = "Ingress to materialize balancers HTTP"
      protocol    = "tcp"
      from_port   = 6876
      to_port     = 6876
      type        = "ingress"
      cidr_blocks = var.materialize_node_ingress_cidrs
    }
    mz_ingress_pgwire = {
      description = "Ingress to materialize balancers pgwire"
      protocol    = "tcp"
      from_port   = 6875
      to_port     = 6875
      type        = "ingress"
      cidr_blocks = var.materialize_node_ingress_cidrs
    }
    mz_ingress_nlb_health_checks = {
      description = "Ingress to materialize balancer health checks and console"
      protocol    = "tcp"
      from_port   = 8080
      to_port     = 8080
      type        = "ingress"
      cidr_blocks = var.materialize_node_ingress_cidrs
    }
    orchestratord_ingress_conversion_webhooks = {
      description                   = "Ingress to materialize orchestratord for conversion webhooks"
      protocol                      = "tcp"
      from_port                     = 8001
      to_port                       = 8001
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  # Makes the caller identity a cluster admin.
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions

  # Disable if the name is too long: name_prefix allows at most 38 characters.
  iam_role_use_name_prefix = var.iam_role_use_name_prefix

  iam_role_permissions_boundary = var.iam_permissions_boundary

  tags = var.tags
}
