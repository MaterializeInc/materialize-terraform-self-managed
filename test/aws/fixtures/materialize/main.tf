provider "aws" {
  region  = var.region
  profile = var.profile != null ? var.profile : null
}


# EKS Cluster
module "eks" {
  source = "../../../../aws/modules/eks"

  name_prefix                              = var.name_prefix
  cluster_version                          = var.cluster_version
  vpc_id                                   = var.vpc_id
  private_subnet_ids                       = var.subnet_ids
  cluster_enabled_log_types                = var.cluster_enabled_log_types
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions
  iam_role_use_name_prefix                 = var.iam_role_use_name_prefix
  materialize_node_ingress_cidrs           = var.materialize_node_ingress_cidrs
  tags                                     = var.tags
}

# EKS Node Group
module "eks_node_group" {
  source = "../../../../aws/modules/eks-node-group"

  cluster_name                      = module.eks.cluster_name
  subnet_ids                        = var.subnet_ids
  node_group_name                   = var.name_prefix
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

# AWS Load Balancer Controller
module "aws_lbc" {
  source = "../../../../aws/modules/aws-lbc"

  name_prefix       = var.name_prefix
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


# Database
module "database" {
  source = "../../../../aws/modules/database"

  name_prefix         = var.name_prefix
  vpc_id              = var.vpc_id
  database_subnet_ids = var.subnet_ids

  postgres_version      = var.postgres_version
  instance_class        = var.instance_class
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  multi_az              = var.multi_az

  database_name     = var.database_name
  database_username = var.database_username
  database_password = var.database_password

  maintenance_window      = var.maintenance_window
  backup_window           = var.backup_window
  backup_retention_period = var.backup_retention_period

  cluster_name              = module.eks.cluster_name
  cluster_security_group_id = module.eks.cluster_security_group_id
  node_security_group_id    = module.eks.node_security_group_id

  tags = var.tags

  depends_on = [module.eks]
}

# Kubernetes provider configuration
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

# Helm provider configuration
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

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }

  load_config_file = false
}

# Cert Manager
module "cert_manager" {
  source = "../../../../kubernetes/modules/cert-manager"

  install_timeout = var.cert_manager_install_timeout
  chart_version   = var.cert_manager_chart_version
  namespace       = var.cert_manager_namespace

  depends_on = [
    module.eks_node_group,
    module.eks,
    module.aws_lbc,
  ]
}

# Self-signed Cluster Issuer
module "self_signed_cluster_issuer" {
  source = "../../../../kubernetes/modules/self-signed-cluster-issuer"

  name_prefix = var.name_prefix
  namespace   = var.cert_manager_namespace

  depends_on = [
    module.cert_manager,
  ]
}

# Materialize Operator
module "operator" {
  source = "../../../../aws/modules/operator"

  name_prefix        = var.name_prefix
  aws_region         = var.region
  operator_namespace = var.operator_namespace
  aws_account_id     = data.aws_caller_identity.current.account_id
  swap_enabled       = var.swap_enabled

  depends_on = [
    module.eks_node_group,
    module.eks,
  ]
}

# Storage (S3)
module "storage" {
  source                   = "../../../../aws/modules/storage"
  name_prefix              = var.name_prefix
  bucket_lifecycle_rules   = var.bucket_lifecycle_rules
  bucket_force_destroy     = var.bucket_force_destroy
  enable_bucket_versioning = var.enable_bucket_versioning
  enable_bucket_encryption = var.enable_bucket_encryption

  # IRSA configuration
  oidc_provider_arn         = module.eks.oidc_provider_arn
  cluster_oidc_issuer_url   = module.eks.cluster_oidc_issuer_url
  service_account_namespace = var.instance_namespace
  service_account_name      = var.instance_name

  tags = var.tags
}

# Materialize Instance
module "materialize_instance" {
  source               = "../../../../kubernetes/modules/materialize-instance"
  instance_name        = var.instance_name
  instance_namespace   = var.instance_namespace
  metadata_backend_url = local.metadata_backend_url
  persist_backend_url  = local.persist_backend_url

  # The password for the external login to the Materialize instance
  external_login_password_mz_system = var.external_login_password_mz_system

  # Materialize license key
  license_key = var.license_key

  # AWS IAM role annotation for service account
  service_account_annotations = {
    "eks.amazonaws.com/role-arn" = module.storage.materialize_s3_role_arn
  }

  issuer_ref = {
    name = module.self_signed_cluster_issuer.issuer_name
    kind = "ClusterIssuer"
  }

  depends_on = [
    module.eks,
    module.database,
    module.storage,
    module.self_signed_cluster_issuer,
    module.operator,
    module.aws_lbc,
    module.eks_node_group,
  ]
}

# Materialize NLB
module "materialize_nlb" {
  source = "../../../../aws/modules/nlb"

  instance_name                    = var.instance_name
  name_prefix                      = var.name_prefix
  namespace                        = var.instance_namespace
  subnet_ids                       = var.subnet_ids
  internal                         = var.internal
  preserve_client_ip               = var.preserve_client_ip
  ingress_cidr_blocks              = var.ingress_cidr_blocks
  node_security_group_id           = module.eks.node_security_group_id
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing
  vpc_id                           = var.vpc_id
  mz_resource_id                   = module.materialize_instance.instance_resource_id

  tags = var.tags

  depends_on = [
    module.materialize_instance
  ]
}

# Local values
locals {
  metadata_backend_url = format(
    "postgres://%s:%s@%s/%s?sslmode=require",
    module.database.db_instance_username,
    urlencode(var.database_password),
    module.database.db_instance_endpoint,
    module.database.db_instance_name
  )

  persist_backend_url = format(
    "s3://%s/system:serviceaccount:%s:%s",
    module.storage.bucket_name,
    var.instance_namespace,
    var.instance_name
  )
}

# Data sources
data "aws_caller_identity" "current" {}
