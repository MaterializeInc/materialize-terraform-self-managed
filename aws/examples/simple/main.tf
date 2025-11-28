provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = var.tags
  }
}

# The ECR public authorization token endpoint isn't in all regions,
# so lets get a new provider just for this purpose.
provider "aws" {
  region  = "us-east-1"
  profile = var.aws_profile
  alias   = "ecrpublic_token_provider"
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecrpublic_token_provider
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region, "--profile", var.aws_profile]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region, "--profile", var.aws_profile]
    }
  }
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region, "--profile", var.aws_profile]
  }

  load_config_file = false
}

# 1. Create network infrastructure
module "networking" {
  source = "../../modules/networking"

  name_prefix = var.name_prefix

  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_vpc_endpoints = true

  tags = var.tags
}

# 2. Create EKS cluster
module "eks" {
  source                                   = "../../modules/eks"
  name_prefix                              = var.name_prefix
  cluster_version                          = "1.32"
  vpc_id                                   = module.networking.vpc_id
  private_subnet_ids                       = module.networking.private_subnet_ids
  cluster_enabled_log_types                = ["api", "audit"]
  enable_cluster_creator_admin_permissions = true
  tags                                     = var.tags

  depends_on = [
    module.networking,
  ]
}

# 2.1 Create base node group for Karpenter and coredns
module "base_node_group" {
  source = "../../modules/eks-node-group"

  cluster_name                      = module.eks.cluster_name
  subnet_ids                        = module.networking.private_subnet_ids
  node_group_name                   = "${var.name_prefix}-base"
  instance_types                    = local.instance_types_base
  swap_enabled                      = false
  min_size                          = 2
  max_size                          = 3
  desired_size                      = 2
  labels                            = local.base_node_labels
  cluster_service_cidr              = module.eks.cluster_service_cidr
  cluster_primary_security_group_id = module.eks.node_security_group_id
  tags                              = var.tags
}

# 2.2 Install Karpenter to manage creation of additional nodes
module "karpenter" {
  source = "../../modules/karpenter"

  name_prefix             = var.name_prefix
  cluster_name            = module.eks.cluster_name
  cluster_endpoint        = module.eks.cluster_endpoint
  oidc_provider_arn       = module.eks.oidc_provider_arn
  cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url
  node_selector           = local.base_node_labels

  helm_repo_username = data.aws_ecrpublic_authorization_token.token.user_name
  helm_repo_password = data.aws_ecrpublic_authorization_token.token.password

  depends_on = [
    module.eks,
    module.base_node_group,
    module.networking,
  ]
}

# Create a generic nodeclass and nodepool for all workloads except Materialize.
module "ec2nodeclass_generic" {
  source = "../../modules/karpenter-ec2nodeclass"

  name               = local.nodeclass_name_generic
  ami_selector_terms = local.ami_selector_terms
  instance_types     = local.instance_types_generic
  instance_profile   = module.karpenter.node_instance_profile
  security_group_ids = [module.eks.node_security_group_id]
  subnet_ids         = module.networking.private_subnet_ids
  swap_enabled       = false
  tags               = var.tags

  depends_on = [
    module.karpenter,
  ]
}

module "nodepool_generic" {
  source = "../../modules/karpenter-nodepool"

  name           = local.nodeclass_name_generic
  nodeclass_name = local.nodeclass_name_generic
  instance_types = local.instance_types_generic
  node_labels    = local.generic_node_labels
  expire_after   = "168h"

  kubeconfig_data = local.kubeconfig_data

  depends_on = [
    module.karpenter,
    module.ec2nodeclass_generic,
  ]
}

# Create a dedicated nodeclass and nodepool for Materialize pods.
module "ec2nodeclass_materialize" {
  source = "../../modules/karpenter-ec2nodeclass"

  name               = local.nodeclass_name_materialize
  ami_selector_terms = local.ami_selector_terms
  instance_types     = local.instance_types_materialize
  instance_profile   = module.karpenter.node_instance_profile
  security_group_ids = [module.eks.node_security_group_id]
  subnet_ids         = module.networking.private_subnet_ids
  swap_enabled       = true
  tags               = var.tags

  depends_on = [
    module.karpenter,
  ]
}

module "nodepool_materialize" {
  source = "../../modules/karpenter-nodepool"

  name           = local.nodeclass_name_materialize
  nodeclass_name = local.nodeclass_name_materialize
  instance_types = local.instance_types_materialize
  node_labels    = local.materialize_node_labels
  node_taints    = local.materialize_node_taints
  expire_after   = "Never"

  kubeconfig_data = local.kubeconfig_data

  depends_on = [
    module.karpenter,
    module.ec2nodeclass_materialize,
  ]
}

# 3. Install AWS Load Balancer Controller
module "aws_lbc" {
  source = "../../modules/aws-lbc"

  name_prefix       = var.name_prefix
  eks_cluster_name  = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer_url   = module.eks.cluster_oidc_issuer_url
  vpc_id            = module.networking.vpc_id
  region            = var.aws_region
  node_selector     = local.generic_node_labels

  tags = var.tags

  depends_on = [
    module.eks,
    module.nodepool_generic,
  ]
}

# 5. Install Certificate Manager for TLS
module "cert_manager" {
  source = "../../../kubernetes/modules/cert-manager"

  node_selector = local.generic_node_labels

  depends_on = [
    module.networking,
    module.eks,
    module.nodepool_generic,
    module.aws_lbc,
  ]
}

module "self_signed_cluster_issuer" {
  source = "../../../kubernetes/modules/self-signed-cluster-issuer"

  name_prefix = var.name_prefix

  depends_on = [
    module.cert_manager,
  ]
}

# 6. Install Materialize Operator
module "operator" {
  source = "../../modules/operator"

  name_prefix    = var.name_prefix
  aws_region     = var.aws_region
  aws_account_id = data.aws_caller_identity.current.account_id

  # tolerations and node selector for all mz instance workloads on AWS
  instance_pod_tolerations = local.materialize_tolerations
  instance_node_selector   = local.materialize_node_labels

  # node selector for operator and metrics-server workloads
  operator_node_selector = local.generic_node_labels


  depends_on = [
    module.eks,
    module.networking,
    module.nodepool_generic,
  ]
}

resource "random_password" "database_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "external_login_password_mz_system" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# 7. Setup dedicated database instance for Materialize
module "database" {
  source                    = "../../modules/database"
  name_prefix               = var.name_prefix
  postgres_version          = "15"
  instance_class            = "db.t3.large"
  allocated_storage         = 50
  max_allocated_storage     = 100
  database_name             = "materialize"
  database_username         = "materialize"
  database_password         = random_password.database_password.result
  multi_az                  = false
  database_subnet_ids       = module.networking.private_subnet_ids
  vpc_id                    = module.networking.vpc_id
  cluster_name              = module.eks.cluster_name
  cluster_security_group_id = module.eks.cluster_security_group_id
  node_security_group_id    = module.eks.node_security_group_id

  tags = var.tags
}

# 8. Setup S3 bucket for Materialize
module "storage" {
  source                 = "../../modules/storage"
  name_prefix            = var.name_prefix
  bucket_lifecycle_rules = []
  bucket_force_destroy   = true

  # For testing purposes, we are disabling encryption and versioning to allow for easier cleanup
  # This should be enabled in production environments for security and data integrity
  enable_bucket_versioning = false
  enable_bucket_encryption = false

  # IRSA configuration
  oidc_provider_arn         = module.eks.oidc_provider_arn
  cluster_oidc_issuer_url   = module.eks.cluster_oidc_issuer_url
  service_account_namespace = local.materialize_instance_namespace
  service_account_name      = local.materialize_instance_name

  tags = var.tags
}

# 9. Setup Materialize instance
module "materialize_instance" {
  source               = "../../../kubernetes/modules/materialize-instance"
  instance_name        = local.materialize_instance_name
  instance_namespace   = local.materialize_instance_namespace
  metadata_backend_url = local.metadata_backend_url
  persist_backend_url  = local.persist_backend_url

  # The password for the external login to the Materialize instance
  external_login_password_mz_system = random_password.external_login_password_mz_system.result
  authenticator_kind                = "Password"

  # AWS IAM role annotation for service account
  service_account_annotations = {
    "eks.amazonaws.com/role-arn" = module.storage.materialize_s3_role_arn
  }

  license_key = var.license_key

  issuer_ref = {
    name = module.self_signed_cluster_issuer.issuer_name
    kind = "ClusterIssuer"
  }

  depends_on = [
    module.eks,
    module.database,
    module.storage,
    module.networking,
    module.self_signed_cluster_issuer,
    module.operator,
    module.aws_lbc,
    module.nodepool_materialize,
  ]
}

# 10. Setup dedicated NLB for Materialize instance
module "materialize_nlb" {
  source = "../../modules/nlb"

  instance_name                    = local.materialize_instance_name
  name_prefix                      = var.name_prefix
  namespace                        = local.materialize_instance_namespace
  subnet_ids                       = module.networking.private_subnet_ids
  enable_cross_zone_load_balancing = true
  vpc_id                           = module.networking.vpc_id
  mz_resource_id                   = module.materialize_instance.instance_resource_id

  tags = var.tags

  depends_on = [
    module.materialize_instance
  ]
}

locals {
  materialize_instance_namespace = "materialize-environment"
  materialize_instance_name      = "main"

  # Common node scheduling configuration
  base_node_labels = {
    "workload" = "base"
  }

  generic_node_labels = {
    "workload" = "generic"
  }

  materialize_node_labels = {
    "materialize.cloud/swap" = "true"
    "workload"               = "materialize-instance"
  }

  materialize_node_taints = [
    {
      key    = "materialize.cloud/workload"
      value  = "materialize-instance"
      effect = "NoSchedule"
    }
  ]

  materialize_tolerations = [
    {
      key      = "materialize.cloud/workload"
      value    = "materialize-instance"
      operator = "Equal"
      effect   = "NoSchedule"
    }
  ]

  database_statement_timeout = "15min"

  metadata_backend_url = format(
    "postgres://%s:%s@%s/%s?sslmode=require&options=-c%%20statement_timeout%%3D%s",
    module.database.db_instance_username,
    urlencode(random_password.database_password.result),
    module.database.db_instance_endpoint,
    module.database.db_instance_name,
    local.database_statement_timeout
  )

  persist_backend_url = format(
    "s3://%s/system:serviceaccount:%s:%s",
    module.storage.bucket_name,
    local.materialize_instance_namespace,
    local.materialize_instance_name
  )

  ami_selector_terms = [{ "alias" : "bottlerocket@latest" }]

  instance_types_base        = ["t4g.medium"]
  instance_types_generic     = ["t4g.xlarge"]
  instance_types_materialize = ["r7gd.2xlarge"]

  nodeclass_name_generic     = "generic"
  nodeclass_name_materialize = "materialize"

  kubeconfig_data = jsonencode({
    "apiVersion" : "v1",
    "kind" : "Config",
    "clusters" : [
      {
        "name" : module.eks.cluster_name,
        "cluster" : {
          "certificate-authority-data" : module.eks.cluster_certificate_authority_data,
          "server" : module.eks.cluster_endpoint,
        },
      },
    ],
    "contexts" : [
      {
        "name" : module.eks.cluster_name,
        "context" : {
          "cluster" : module.eks.cluster_name,
          "user" : module.eks.cluster_name,
        },
      },
    ],
    "current-context" : module.eks.cluster_name,
    "users" : [
      {
        "name" : module.eks.cluster_name,
        "user" : {
          "exec" : {
            "apiVersion" : "client.authentication.k8s.io/v1beta1",
            "command" : "aws",
            "args" : [
              "eks",
              "get-token",
              "--cluster-name",
              module.eks.cluster_name,
              "--region",
              var.aws_region,
              "--profile",
              var.aws_profile,
            ]
          }
        },
      },
    ],
  })
}

data "aws_caller_identity" "current" {}
