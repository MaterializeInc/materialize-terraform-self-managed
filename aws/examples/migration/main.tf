# =============================================================================
# Migration Reference Configuration
# =============================================================================
# Copy this file and adapt the values to your existing infrastructure. Module
# paths must match where the state migration moves resources; if you rename a
# module, update the state mv commands to match.
#
# Defaults match the old setup so the migration is zero-downtime:
# 1. NAT gateways: one per AZ, as in the old defaults
# 2. Node groups: existing node groups kept, Karpenter commented out
# 3. Instances: set materialize_instance_name; add others in locals
#
# After the migration is verified you can enable Karpenter and update node groups.
# =============================================================================

# -----------------------------------------------------------------------------
# Providers
# -----------------------------------------------------------------------------

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  # MIGRATION: the old module set no default_tags. Uncomment after migration is verified.
  # default_tags {
  #   tags = var.tags
  # }
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

# lazy_load (alekc/kubectl v2.4.0+) defers kubeconfig resolution until first use.
# Without it, plans fail with an empty REST config while cluster outputs are unknown.
# See https://registry.terraform.io/providers/alekc/kubectl/latest/docs#troubleshooting
provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region, "--profile", var.aws_profile]
  }

  load_config_file = false
  lazy_load        = true
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
# State path: module.networking.module.vpc.*
# Match your existing VPC: aws ec2 describe-vpcs --vpc-ids <your-vpc-id>

module "networking" {
  source      = "../../modules/networking"
  name_prefix = var.name_prefix

  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
  single_nat_gateway   = var.single_nat_gateway
  enable_vpc_endpoints = var.enable_vpc_endpoints

  tags = var.tags
}

# -----------------------------------------------------------------------------
# EKS Cluster
# -----------------------------------------------------------------------------
# State path: module.eks.module.eks.*
# Match your existing cluster_version: aws eks describe-cluster --name <your-cluster>

module "eks" {
  source      = "../../modules/eks"
  name_prefix = var.name_prefix

  cluster_version                          = var.cluster_version
  vpc_id                                   = module.networking.vpc_id
  private_subnet_ids                       = module.networking.private_subnet_ids
  cluster_enabled_log_types                = ["api", "audit", "authenticator", "controllerManager", "scheduler"] # MIGRATION: Match old module defaults
  enable_cluster_creator_admin_permissions = true
  materialize_node_ingress_cidrs           = var.ingress_cidr_blocks
  k8s_apiserver_authorized_networks        = var.k8s_apiserver_authorized_networks

  tags = var.tags

  depends_on = [module.networking]
}

# -----------------------------------------------------------------------------
# Base Node Group (for CoreDNS and system workloads)
# -----------------------------------------------------------------------------
# State path: module.base_node_group.module.node_group.*
# MIGRATION: replaces the old EKS module's system node group. Match its
# instance types and sizes.

module "base_node_group" {
  source = "../../modules/eks-node-group"

  cluster_name = module.eks.cluster_name
  subnet_ids   = module.networking.private_subnet_ids
  # MIGRATION: the old EKS module's names; changing them replaces the node
  # group and launch template.
  node_group_name                   = var.name_prefix
  launch_template_name              = "${var.name_prefix}-system"
  instance_types                    = var.base_instance_types
  swap_enabled                      = false
  min_size                          = var.base_node_min_size
  max_size                          = var.base_node_max_size
  desired_size                      = var.base_node_desired_size
  labels                            = local.base_node_labels
  cluster_service_cidr              = module.eks.cluster_service_cidr
  cluster_primary_security_group_id = module.eks.node_security_group_id
  aws_region                        = var.aws_region
  aws_profile                       = var.aws_profile
  # Resolved at the root so they are known at plan time (see the
  # eks-node-group partition variable).
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id

  tags = var.tags
}

# MIGRATION: CoreDNS was not managed by the old setup (EKS manages it by
# default). Uncomment after migration is verified to manage it with Terraform.
#
# module "coredns" {
#   source = "../../../kubernetes/modules/coredns"
#
#   node_selector                      = local.base_node_labels
#   disable_default_coredns_autoscaler = false
#   kubeconfig_data                    = local.kubeconfig_data
#
#   depends_on = [module.eks, module.base_node_group, module.networking]
# }

# -----------------------------------------------------------------------------
# Materialize Node Group
# -----------------------------------------------------------------------------
# State path: module.mz_node_group.module.node_group.*
# MIGRATION: replaces the old materialize_node_group. Match its instance types and sizes.

module "mz_node_group" {
  source = "../../modules/eks-node-group"

  cluster_name    = module.eks.cluster_name
  subnet_ids      = module.networking.private_subnet_ids
  node_group_name = "${var.name_prefix}-mz-swap"
  instance_types  = var.mz_instance_types
  swap_enabled    = true
  min_size        = var.mz_node_min_size
  max_size        = var.mz_node_max_size
  desired_size    = var.mz_node_desired_size
  labels          = local.materialize_node_labels
  # MIGRATION: the old module set no EKS taints. Uncomment after migration is verified.
  # node_taints                       = local.materialize_node_taints
  cluster_service_cidr              = module.eks.cluster_service_cidr
  cluster_primary_security_group_id = module.eks.node_security_group_id
  aws_region                        = var.aws_region
  aws_profile                       = var.aws_profile
  # Resolved at the root so they are known at plan time (see the
  # eks-node-group partition variable).
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id

  tags = merge(var.tags, {
    Swap = "true" # MIGRATION: Match old module tag on materialize node group
  })

  depends_on = [module.eks, module.base_node_group]
}

# -----------------------------------------------------------------------------
# Karpenter (Node Autoscaling) - COMMENTED OUT FOR MIGRATION
# -----------------------------------------------------------------------------
# MIGRATION: commented out to keep the existing node groups. After migration is
# verified: uncomment, drain workloads from the static node groups to Karpenter,
# then remove mz_node_group.

# module "karpenter" {
#   source = "../../modules/karpenter"
#
#   name_prefix             = var.name_prefix
#   cluster_name            = module.eks.cluster_name
#   cluster_endpoint        = module.eks.cluster_endpoint
#   oidc_provider_arn       = module.eks.oidc_provider_arn
#   cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url
#   node_selector           = local.base_node_labels
#
#   depends_on = [module.eks, module.base_node_group, module.networking]
# }
#
# module "ec2nodeclass_generic" {
#   source = "../../modules/karpenter-ec2nodeclass"
#
#   name               = "generic"
#   ami_selector_terms = [{ "alias" : "bottlerocket@latest" }]
#   instance_types     = ["t4g.xlarge"]
#   instance_profile   = module.karpenter.node_instance_profile
#   security_group_ids = [module.eks.node_security_group_id]
#   subnet_ids         = module.networking.private_subnet_ids
#   swap_enabled       = false
#
#   tags = var.tags
#
#   depends_on = [module.karpenter]
# }
#
# module "nodepool_generic" {
#   source = "../../modules/karpenter-nodepool"
#
#   name           = "generic"
#   nodeclass_name = "generic"
#   instance_types = ["t4g.xlarge"]
#   node_labels    = local.generic_node_labels
#   expire_after   = "168h"
#
#   kubeconfig_data = local.kubeconfig_data
#
#   depends_on = [module.karpenter, module.ec2nodeclass_generic, module.coredns]
# }
#
# module "ec2nodeclass_materialize" {
#   source = "../../modules/karpenter-ec2nodeclass"
#
#   name               = "materialize"
#   ami_selector_terms = [{ "alias" : "bottlerocket@latest" }]
#   instance_types     = ["r7gd.2xlarge"]
#   instance_profile   = module.karpenter.node_instance_profile
#   security_group_ids = [module.eks.node_security_group_id]
#   subnet_ids         = module.networking.private_subnet_ids
#   swap_enabled       = true
#
#   tags = var.tags
#
#   depends_on = [module.karpenter]
# }
#
# module "nodepool_materialize" {
#   source = "../../modules/karpenter-nodepool"
#
#   name           = "materialize"
#   nodeclass_name = "materialize"
#   instance_types = ["r7gd.2xlarge"]
#   node_labels    = local.materialize_node_labels
#   node_taints    = local.materialize_node_taints
#   expire_after   = "Never"
#
#   kubeconfig_data = local.kubeconfig_data
#
#   depends_on = [module.karpenter, module.ec2nodeclass_materialize, module.coredns]
# }

# -----------------------------------------------------------------------------
# AWS Load Balancer Controller
# -----------------------------------------------------------------------------

module "aws_lbc" {
  source = "../../modules/aws-lbc"

  name_prefix       = var.name_prefix
  eks_cluster_name  = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer_url   = module.eks.cluster_oidc_issuer_url
  vpc_id            = module.networking.vpc_id
  region            = var.aws_region
  node_selector     = local.generic_node_labels

  depends_on = [module.eks, module.base_node_group]
}

# -----------------------------------------------------------------------------
# Certificate Manager
# -----------------------------------------------------------------------------

module "cert_manager" {
  source = "../../../kubernetes/modules/cert-manager"

  node_selector = local.generic_node_labels

  depends_on = [module.networking, module.eks, module.base_node_group, module.aws_lbc]
}

module "self_signed_cluster_issuer" {
  source = "../../../kubernetes/modules/self-signed-cluster-issuer"

  name_prefix = var.name_prefix

  depends_on = [module.cert_manager]
}

# -----------------------------------------------------------------------------
# Database (RDS PostgreSQL)
# -----------------------------------------------------------------------------
# State path: module.database.module.db.module.db_instance.*
# MIGRATION: values MUST match your existing RDS instance or Terraform will modify
# or recreate it. Check: aws rds describe-db-instances --db-instance-identifier <your-db-id>

module "database" {
  source = "../../modules/database"

  name_prefix = var.name_prefix

  postgres_version      = var.postgres_version
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage

  database_name     = "materialize"
  database_username = "materialize"
  database_password = var.old_db_password

  multi_az            = var.db_multi_az
  database_subnet_ids = module.networking.private_subnet_ids
  vpc_id              = module.networking.vpc_id

  cluster_name              = module.eks.cluster_name
  cluster_security_group_id = module.eks.cluster_security_group_id
  node_security_group_id    = module.eks.node_security_group_id

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Storage (S3)
# -----------------------------------------------------------------------------
# State path: module.storage.*
# MIGRATION: the bucket name's random suffix comes from random_id, which moves
# with the state, so the name is preserved.

module "storage" {
  source = "../../modules/storage"

  name_prefix = var.name_prefix
  # MIGRATION: Preserve existing lifecycle rules from old module
  bucket_lifecycle_rules = [
    {
      id                                 = "cleanup"
      enabled                            = true
      prefix                             = ""
      transition_days                    = 90
      transition_storage_class           = "STANDARD_IA"
      noncurrent_version_expiration_days = 90
    }
  ]
  bucket_force_destroy = true # Set to false for production!

  enable_bucket_versioning = true # MIGRATION: Match your existing setting
  enable_bucket_encryption = true

  # IRSA configuration
  oidc_provider_arn         = module.eks.oidc_provider_arn
  cluster_oidc_issuer_url   = module.eks.cluster_oidc_issuer_url
  service_account_namespace = local.materialize_instance_namespace
  service_account_name      = local.materialize_instance_name

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Materialize Operator
# -----------------------------------------------------------------------------
# State path: module.operator.*

module "operator" {
  source = "../../modules/operator"

  name_prefix    = var.name_prefix
  aws_region     = var.aws_region
  aws_account_id = data.aws_caller_identity.current.account_id

  instance_pod_tolerations = local.materialize_tolerations
  instance_node_selector   = local.materialize_node_labels
  operator_node_selector   = local.generic_node_labels

  depends_on = [module.eks, module.networking, module.mz_node_group]

  install_metrics_server = true

  # MIGRATION: the old module set TLS via defaultCertificateSpecs in the operator Helm values.
  helm_values = var.use_self_signed_cluster_issuer ? {
    tls = {
      defaultCertificateSpecs = {
        balancerdExternal = {
          dnsNames = ["balancerd"]
          issuerRef = {
            name = "${var.name_prefix}-root-ca"
            kind = "ClusterIssuer"
          }
        }
        consoleExternal = {
          dnsNames = ["console"]
          issuerRef = {
            name = "${var.name_prefix}-root-ca"
            kind = "ClusterIssuer"
          }
        }
        internal = {
          issuerRef = {
            name = "${var.name_prefix}-root-ca"
            kind = "ClusterIssuer"
          }
        }
      }
    }
  } : {}
}

# -----------------------------------------------------------------------------
# Materialize Instance Namespace
# -----------------------------------------------------------------------------
# State path: kubernetes_namespace.instance_namespaces["<instance_name>"]
#
# MIGRATION: this and the instance resources below lived in the old operator
# module; the moved blocks further down move them to the root.

resource "kubernetes_namespace" "instance_namespaces" {
  for_each = local.materialize_instances

  metadata {
    name = each.value.namespace
  }

  depends_on = [module.eks]
}

# -----------------------------------------------------------------------------
# Materialize Backend Secret
# -----------------------------------------------------------------------------
# State path: kubernetes_secret.materialize_backends["<instance_name>"]

resource "kubernetes_secret" "materialize_backends" {
  for_each = local.materialize_instances

  metadata {
    name      = "${each.key}-materialize-backend"
    namespace = each.value.namespace
  }

  data = {
    # MIGRATION: both URLs must match the old module's values exactly.
    metadata_backend_url = format(
      "postgres://%s:%s@%s/%s?sslmode=require",
      module.database.db_instance_username,
      urlencode(var.old_db_password),
      module.database.db_instance_endpoint,
      each.value.database_name
    )
    persist_backend_url = format(
      "s3://%s/%s-%s:serviceaccount:%s:%s",
      module.storage.bucket_name,
      var.environment,
      each.key,
      each.value.namespace,
      each.key
    )
    license_key                       = var.license_key
    external_login_password_mz_system = var.external_login_password_mz_system # your existing mz_system password
  }

  depends_on = [
    kubernetes_namespace.instance_namespaces,
    module.database,
    module.storage,
  ]
}

# -----------------------------------------------------------------------------
# Materialize Instance Manifest
# -----------------------------------------------------------------------------
# State path: kubernetes_manifest.materialize_instances["<instance_name>"]
# MIGRATION: kubernetes_manifest (not kubectl_manifest) to match the migrated state.

resource "kubernetes_manifest" "materialize_instances" {
  for_each = local.materialize_instances

  field_manager {
    name            = "terraform"
    force_conflicts = true
  }

  manifest = {
    apiVersion = "materialize.cloud/v1alpha1"
    kind       = "Materialize"
    metadata = {
      name      = each.key
      namespace = each.value.namespace
    }
    spec = {
      backendSecretName    = "${each.key}-materialize-backend"
      authenticatorKind    = "Password"
      environmentdImageRef = var.environmentd_image_ref
      forceRollout         = var.force_rollout
      requestRollout       = var.request_rollout

      serviceAccountAnnotations = {
        "eks.amazonaws.com/role-arn" = module.storage.materialize_s3_role_arn
      }

      environmentdResourceRequirements = {
        limits = {
          memory = "4Gi"
        }
        requests = {
          cpu    = "2"
          memory = "4Gi"
        }
      }

      balancerdResourceRequirements = {
        limits = {
          memory = "256Mi"
        }
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
      }
    }
  }

  wait {
    fields = {
      "status.resourceId" = ".*"
    }
  }

  depends_on = [
    kubernetes_secret.materialize_backends,
    kubernetes_namespace.instance_namespaces,
    module.operator,
  ]
}

# -----------------------------------------------------------------------------
# Data Source: Materialize Instances
# -----------------------------------------------------------------------------
# State path: data.kubernetes_resource.materialize_instances["<instance_name>"]
# Provides the instance resource IDs used by the NLB module.

data "kubernetes_resource" "materialize_instances" {
  for_each = local.materialize_instances

  api_version = "materialize.cloud/v1alpha1"
  kind        = "Materialize"

  metadata {
    name      = each.key
    namespace = each.value.namespace
  }

  depends_on = [kubernetes_manifest.materialize_instances]
}

# -----------------------------------------------------------------------------
# Moved Blocks for Migration
# -----------------------------------------------------------------------------
# Move instance resources from the old operator module to the root on apply.
# Safe to remove once the migration is applied and verified.

moved {
  from = module.operator.kubernetes_namespace.instance_namespaces
  to   = kubernetes_namespace.instance_namespaces
}

moved {
  from = module.operator.kubernetes_secret.materialize_backends
  to   = kubernetes_secret.materialize_backends
}

moved {
  from = module.operator.kubernetes_manifest.materialize_instances
  to   = kubernetes_manifest.materialize_instances
}

moved {
  from = module.operator.kubernetes_job.db_init_job
  to   = kubernetes_job.db_init_job
}

moved {
  from = module.operator.data.kubernetes_resource.materialize_instances
  to   = data.kubernetes_resource.materialize_instances
}

# -----------------------------------------------------------------------------
# Network Load Balancer
# -----------------------------------------------------------------------------
# State path: module.nlb["<instance_name>"].*
# MIGRATION: for_each matches the migrated state structure.

module "nlb" {
  for_each = local.materialize_instances
  source   = "../../modules/nlb"

  instance_name = each.key
  name_prefix   = var.name_prefix
  # MIGRATION: keeps the old NLB name; removing this line renames and so
  # recreates the NLB.
  nlb_name                         = "${var.name_prefix}-${each.key}"
  namespace                        = each.value.namespace
  subnet_ids                       = var.internal_load_balancer ? module.networking.private_subnet_ids : module.networking.public_subnet_ids
  internal                         = var.internal_load_balancer
  enable_cross_zone_load_balancing = true
  vpc_id                           = module.networking.vpc_id
  mz_resource_id                   = data.kubernetes_resource.materialize_instances[each.key].object.status.resourceId
  node_security_group_id           = module.eks.node_security_group_id
  ingress_cidr_blocks              = var.ingress_cidr_blocks
  # MIGRATION: old NLBs had no security group and adding one recreates the NLB.
  create_security_group = false

  depends_on = [module.operator]
}

# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------

locals {
  materialize_instance_namespace = var.materialize_instance_namespace
  materialize_instance_name      = var.materialize_instance_name

  # MIGRATION: add any other existing instances here. database_name must match
  # the old module's coalesce(instance.database_name, instance.name).
  materialize_instances = {
    (local.materialize_instance_name) = {
      namespace     = local.materialize_instance_namespace
      database_name = local.materialize_instance_name # Defaults to instance name (old module behavior)
    }
  }

  base_node_labels = {
    "workload" = "system" # MIGRATION: Match old module label. Change to "base" after migration.
  }

  # MIGRATION: "system" because the old module set no nodeSelectors, so these pods
  # ran on system nodes. After migration, switch to "generic" with dedicated nodes
  # (or Karpenter).
  generic_node_labels = {
    "workload" = "system"
  }

  materialize_node_labels = {
    "materialize.cloud/swap" = "true"
    "workload"               = "materialize-instance"
  }

  materialize_tolerations = [
    {
      key      = "materialize.cloud/workload"
      value    = "materialize-instance"
      operator = "Equal"
      effect   = "NoSchedule"
    }
  ]

  metadata_backend_url = format(
    "postgres://%s:%s@%s/%s?sslmode=require",
    module.database.db_instance_username,
    urlencode(var.old_db_password),
    module.database.db_instance_endpoint,
    local.materialize_instance_name
  )

  persist_backend_url = format(
    "s3://%s/%s-%s:serviceaccount:%s:%s",
    module.storage.bucket_name,
    var.environment,
    local.materialize_instance_name,
    local.materialize_instance_namespace,
    local.materialize_instance_name
  )

}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
