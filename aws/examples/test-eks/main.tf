
provider "aws" {
  region  = var.region
  profile = var.profile
}


provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

module "eks" {
  source = "../../modules/eks"

  name_prefix                              = var.cluster_name
  cluster_version                          = var.cluster_version
  vpc_id                                   = var.vpc_id
  private_subnet_ids                       = var.subnet_ids
  cluster_enabled_log_types                = var.cluster_enabled_log_types
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions
  iam_role_use_name_prefix                 = var.iam_role_use_name_prefix
  tags                                     = var.tags
}

module "eks_node_group" {
  count  = var.skip_node_group ? 0 : 1
  source = "../../modules/eks-node-group"

  cluster_name                      = module.eks.cluster_name
  subnet_ids                        = var.subnet_ids
  node_group_name                   = var.cluster_name
  cluster_service_cidr              = module.eks.cluster_service_cidr
  cluster_primary_security_group_id = module.eks.node_security_group_id
  min_size                          = var.min_nodes
  max_size                          = var.max_nodes
  desired_size                      = var.desired_nodes
  instance_types                    = var.instance_types
  capacity_type                     = var.capacity_type
  swap_enabled                      = var.swap_enabled
  labels                            = var.node_labels
  iam_role_use_name_prefix          = var.iam_role_use_name_prefix
  tags                              = var.tags

  depends_on = [module.eks]
}

module "aws_lbc" {
  count  = var.skip_aws_lbc ? 0 : 1
  source = "../../modules/aws-lbc"

  name_prefix       = var.cluster_name
  eks_cluster_name  = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer_url   = module.eks.cluster_oidc_issuer_url
  vpc_id            = var.vpc_id
  region            = var.region
  tags              = var.tags

  depends_on = [
    module.eks,
    module.eks_node_group,
  ]
}
