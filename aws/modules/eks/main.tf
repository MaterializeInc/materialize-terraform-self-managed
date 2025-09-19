module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name = "${var.name_prefix}-eks"

  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  cluster_endpoint_public_access = true

  cluster_enabled_log_types = var.cluster_enabled_log_types

  node_security_group_additional_rules = {
    mz_ingress_http = {
      description      = "Ingress to materialize balancers HTTP"
      protocol         = "tcp"
      from_port        = 6876
      to_port          = 6876
      type             = "ingress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
    mz_ingress_pgwire = {
      description      = "Ingress to materialize balancers pgwire"
      protocol         = "tcp"
      from_port        = 6875
      to_port          = 6875
      type             = "ingress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
    mz_ingress_nlb_health_checks = {
      description      = "Ingress to materialize balancer health checks and console"
      protocol         = "tcp"
      from_port        = 8080
      to_port          = 8080
      type             = "ingress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  # Cluster access entry
  # To add the current caller identity as an administrator
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions

  # useful to disable this when prefix might be too long and hit following char limit
  # expected length of name_prefix to be in the range (1 - 38)
  iam_role_use_name_prefix = var.iam_role_use_name_prefix

  tags = var.tags
}

# System nodepool for running critical system pods
module "system_nodepool" {
  source  = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "~> 20.0"

  name           = "${var.name_prefix}-system"
  cluster_name   = module.eks.cluster_name
  subnet_ids     = var.private_subnet_ids
  desired_size   = var.system_nodepool_desired_size
  min_size       = var.system_nodepool_min_size
  max_size       = var.system_nodepool_max_size
  instance_types = var.system_nodepool_instance_types
  capacity_type  = var.system_nodepool_capacity_type
  ami_type       = "AL2_x86_64"

  labels = {
    "workload" = "system"
  }

  taints = [
    {
      key    = "CriticalAddonsOnly"
      value  = ""
      effect = "NO_SCHEDULE"
    }
  ]

  # useful to disable this when prefix might be too long and hit following char limit
  # expected length of name_prefix to be in the range (1 - 38)
  iam_role_use_name_prefix = var.iam_role_use_name_prefix

  cluster_service_cidr              = module.eks.cluster_service_cidr
  cluster_primary_security_group_id = module.eks.cluster_primary_security_group_id

  tags = var.tags

  depends_on = [module.eks]
}
