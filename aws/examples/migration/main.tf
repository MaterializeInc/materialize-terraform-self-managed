# =============================================================================
# Migration Reference Configuration
# =============================================================================
#
# This file serves as a reference for creating your new Terraform configuration.
# Copy this file and adapt the values to match your existing infrastructure.
#
# IMPORTANT: The module paths in this configuration must match where the state
# migration will move resources TO. If you change module names (e.g., rename
# "module.networking" to "module.vpc"), update your state mv commands accordingly.
#
# =============================================================================
#
# MIGRATION STRATEGY FOR ZERO-DOWNTIME
# =============================================================================
#
# This configuration is pre-configured to MATCH the default infrastructure to
# minimize changes during migration. Key settings:
#
# 1. NAT Gateways: Keeps 3 NAT gateways (one per AZ) - matches old defaults setup
# 2. Node Groups: Keeps existing node groups, Karpenter commented out
# 3. Instance Names: Update locals to match the old Materialize instances
#
# After successful migration, you can gradually adopt new features:
# - Enable Karpenter for autoscaling
# - Update node group configurations
#
# =============================================================================

# -----------------------------------------------------------------------------
# Providers
# -----------------------------------------------------------------------------

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = var.tags
  }
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

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
# State path: module.networking.module.vpc.*
#
# Update these values to match your existing VPC configuration.
# Run: aws ec2 describe-vpcs --vpc-ids <your-vpc-id> to get current values.

module "networking" {
  source      = "../../modules/networking"
  name_prefix = var.name_prefix

  # MIGRATION: Update these to match your existing VPC
  vpc_cidr             = "10.0.0.0/16"                                         # Your existing VPC CIDR
  availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]            # Your existing AZs
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]         # Your existing private subnets
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]   # Your existing public subnets

  # MIGRATION: Keep 3 NAT gateways (one per AZ) to match existing setup
  # After migration, you can set to true to reduce costs
  single_nat_gateway = false

  enable_vpc_endpoints = true

  tags = var.tags
}

# -----------------------------------------------------------------------------
# EKS Cluster
# -----------------------------------------------------------------------------
# State path: module.eks.module.eks.*
#
# Update cluster_version to match your existing cluster.
# Run: aws eks describe-cluster --name <your-cluster> to get current values.

module "eks" {
  source      = "../../modules/eks"
  name_prefix = var.name_prefix

  # MIGRATION: Update these to match your existing EKS cluster
  cluster_version                          = "1.32"  # Your existing K8s version
  vpc_id                                   = module.networking.vpc_id
  private_subnet_ids                       = module.networking.private_subnet_ids
  cluster_enabled_log_types                = ["api", "audit"]
  enable_cluster_creator_admin_permissions = true
  # MIGRATION: Preserve old security group rules to avoid replacement
  # Old module included both IPv4 and IPv6. Set ipv6 to [] to remove after migration.
  materialize_node_ingress_cidrs           = var.ingress_cidr_blocks
  materialize_node_ingress_ipv6_cidrs      = ["::/0"]  # Matches old module - remove after migration if not using IPv6
  k8s_apiserver_authorized_networks        = var.k8s_apiserver_authorized_networks

  tags = var.tags

  depends_on = [module.networking]
}

# -----------------------------------------------------------------------------
# Base Node Group (for CoreDNS and system workloads)
# -----------------------------------------------------------------------------
# State path: module.base_node_group.module.node_group.*
#
# MIGRATION: This is equivalent to your old "{prefix}-system" node group.
# Update instance_types, min_size, max_size to match your existing setup.

module "base_node_group" {
  source = "../../modules/eks-node-group"

  cluster_name                      = module.eks.cluster_name
  subnet_ids                        = module.networking.private_subnet_ids
  node_group_name                   = "${var.name_prefix}-base"
  instance_types                    = ["t4g.medium"]  # MIGRATION: Match your existing instance types
  swap_enabled                      = false
  min_size                          = 2   # MIGRATION: Match your existing min_size
  max_size                          = 3   # MIGRATION: Match your existing max_size
  desired_size                      = 2   # MIGRATION: Match your existing desired_size
  labels                            = local.base_node_labels
  cluster_service_cidr              = module.eks.cluster_service_cidr
  cluster_primary_security_group_id = module.eks.node_security_group_id

  tags = var.tags
}

module "coredns" {
  source = "../../../kubernetes/modules/coredns"

  node_selector                      = local.base_node_labels
  disable_default_coredns_autoscaler = false
  kubeconfig_data                    = local.kubeconfig_data

  depends_on = [module.eks, module.base_node_group, module.networking]
}

# -----------------------------------------------------------------------------
# Materialize Node Group
# -----------------------------------------------------------------------------
# State path: module.mz_node_group.module.node_group.*
#
# MIGRATION: This replaces your old materialize_node_group.
# Update instance_types, min_size, max_size to match your existing setup.

module "mz_node_group" {
  source = "../../modules/eks-node-group"

  cluster_name                      = module.eks.cluster_name
  subnet_ids                        = module.networking.private_subnet_ids
  node_group_name                   = "${var.name_prefix}-mz-swap"  # MIGRATION: Match your existing node group name
  instance_types                    = ["r7gd.2xlarge"]              # MIGRATION: Match your existing instance types
  swap_enabled                      = true
  min_size                          = 1   # MIGRATION: Match your existing min_size
  max_size                          = 10  # MIGRATION: Match your existing max_size
  desired_size                      = 1   # MIGRATION: Match your existing desired_size
  labels                            = local.materialize_node_labels
  node_taints                       = local.materialize_node_taints
  cluster_service_cidr              = module.eks.cluster_service_cidr
  cluster_primary_security_group_id = module.eks.node_security_group_id

  tags = var.tags

  depends_on = [module.eks, module.base_node_group]
}

# -----------------------------------------------------------------------------
# Karpenter (Node Autoscaling) - COMMENTED OUT FOR MIGRATION
# -----------------------------------------------------------------------------
# MIGRATION: Karpenter is commented out to preserve your existing node groups.
# After migration is complete and verified, you can:
# 1. Uncomment these modules
# 2. Gradually drain workloads from static node groups to Karpenter
# 3. Remove the mz_node_group module above
#
# Benefits of Karpenter:
# - Automatic scaling based on pod requirements
# - Better bin-packing and cost optimization
# - Faster node provisioning

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

  depends_on = [module.eks, module.base_node_group, module.coredns]
}

# -----------------------------------------------------------------------------
# Certificate Manager
# -----------------------------------------------------------------------------

module "cert_manager" {
  source = "../../../kubernetes/modules/cert-manager"

  node_selector = local.generic_node_labels

  depends_on = [module.networking, module.eks, module.base_node_group, module.aws_lbc, module.coredns]
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
#
# MIGRATION: These values MUST match your existing RDS instance exactly,
# otherwise Terraform will try to modify or recreate the database.
#
# Run: aws rds describe-db-instances --db-instance-identifier <your-db-id>

module "database" {
  source = "../../modules/database"

  name_prefix = var.name_prefix

  # MIGRATION: Match your existing database configuration
  postgres_version      = "17"           # Your existing PostgreSQL version
  instance_class        = "db.m6i.large"  # Your existing instance class
  allocated_storage     = 20             # Your existing allocated storage
  max_allocated_storage = 100            # Your existing max storage

  database_name     = "materialize"                           # Your existing database name
  database_username = "materialize"                           # Your existing username
  database_password = random_password.database_password.result

  multi_az            = false  # Your existing multi-AZ setting
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
#
# MIGRATION: The bucket name includes a random suffix. After migration,
# the random_id resource will be in state and the name will be preserved.

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
  bucket_force_destroy = true  # Set to false for production!

  enable_bucket_versioning = true  # MIGRATION: Match your existing setting
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

  depends_on = [module.eks, module.networking, module.mz_node_group, module.coredns]

  install_metrics_server = true

  # MIGRATION NOTE: The operator module now includes instance namespace, secret,
  # manifest, and db_init_job resources via custom additions below
}

# -----------------------------------------------------------------------------
# Materialize Instance Namespace (part of operator module in migrated state)
# -----------------------------------------------------------------------------
# State path: module.operator.kubernetes_namespace.instance_namespaces["<namespace>"]
#
# MIGRATION: These resources are managed as part of the operator module structure
# to match the migrated state. They use for_each to support multiple instances.

resource "kubernetes_namespace" "instance_namespaces" {
  for_each = local.materialize_instances

  metadata {
    name = each.value.namespace
  }

  depends_on = [module.eks]
}

# -----------------------------------------------------------------------------
# Materialize Backend Secret (part of operator module in migrated state)
# -----------------------------------------------------------------------------
# State path: module.operator.kubernetes_secret.materialize_backends["<instance_name>"]

resource "kubernetes_secret" "materialize_backends" {
  for_each = local.materialize_instances

  metadata {
    name      = "${each.key}-materialize-backend"
    namespace = each.value.namespace
  }

  data = {
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
      each.value.namespace,
      each.key
    )
    license_key = var.license_key
    external_login_password_mz_system = random_password.external_login_password_mz_system.result
  }

  depends_on = [
    kubernetes_namespace.instance_namespaces,
    module.database,
    module.storage,
  ]
}

# -----------------------------------------------------------------------------
# Materialize Instance Manifest (part of operator module in migrated state)
# -----------------------------------------------------------------------------
# State path: module.operator.kubernetes_manifest.materialize_instances["<instance_name>"]
#
# MIGRATION: Uses kubernetes_manifest (not kubectl_manifest) to match migrated state

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
      environmentdImageRef = "materialize/environmentd:v26.7.0"
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
# Database Initialization Job (part of operator module in migrated state)
# -----------------------------------------------------------------------------
# State path: module.operator.kubernetes_job.db_init_job["<instance_name>-<db_name>"]
#
# MIGRATION: This handles database initialization for each instance

resource "kubernetes_job" "db_init_job" {
  for_each = {
    for k, v in local.materialize_instances : "${k}-${k}_db" => merge(v, { instance_name = k })
  }

  metadata {
    name      = "db-init-${each.value.instance_name}"
    namespace = each.value.namespace
  }

  spec {
    template {
      metadata {}
      spec {
        restart_policy = "Never"

        container {
          name  = "db-init"
          image = "postgres:15"

          command = ["/bin/sh", "-c"]
          args = [
            "PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c 'CREATE DATABASE IF NOT EXISTS ${each.value.instance_name}_db' || true"
          ]

          env {
            name  = "DB_HOST"
            value = module.database.db_instance_endpoint
          }
          env {
            name  = "DB_USER"
            value = module.database.db_instance_username
          }
          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.materialize_backends[each.value.instance_name].metadata[0].name
                key  = "metadata_backend_url"
              }
            }
          }
          env {
            name  = "DB_NAME"
            value = module.database.db_instance_name
          }
        }
      }
    }

    backoff_limit = 4
  }

  wait_for_completion = true

  depends_on = [
    kubernetes_secret.materialize_backends,
    module.database,
  ]
}

# -----------------------------------------------------------------------------
# Data Source: Materialize Instances (part of operator module in migrated state)
# -----------------------------------------------------------------------------
# State path: module.operator.kubernetes_resource.materialize_instances["<instance_name>"]
#
# MIGRATION: Data source to retrieve instance resource IDs (used by NLB module)

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
# These moved blocks automatically migrate resources from the old operator module
# structure to the new root-level structure during terraform apply.
# After migration is complete and verified, these blocks can be removed.

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
#
# MIGRATION: This uses for_each to match the migrated state structure

module "nlb" {
  for_each = local.materialize_instances
  source   = "../../modules/nlb"

  instance_name                    = each.key
  name_prefix                      = var.name_prefix
  # MIGRATION: Preserve old NLB naming pattern: ${name_prefix}-${instance_name}
  # This avoids NLB recreation during migration. After migration is verified,
  # you can remove this line to use the new name_prefix-based naming.
  nlb_name                         = "${var.name_prefix}-${each.key}"
  namespace                        = each.value.namespace
  subnet_ids                       = var.internal_load_balancer ? module.networking.private_subnet_ids : module.networking.public_subnet_ids
  internal                         = var.internal_load_balancer
  enable_cross_zone_load_balancing = true
  vpc_id                           = module.networking.vpc_id
  mz_resource_id                   = data.kubernetes_resource.materialize_instances[each.key].object.status.resourceId
  node_security_group_id           = module.eks.node_security_group_id
  ingress_cidr_blocks              = var.ingress_cidr_blocks

  depends_on = [module.operator]
}

# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------

locals {
  # MIGRATION: CRITICAL - Update these to match your existing Materialize instance!
  # Run: kubectl get materialize -A to see your current instances
  # Example: If you have instance "analytics" in namespace "materialize-environment", use those values
  materialize_instance_namespace = "materialize-environment"  # Your existing namespace
  materialize_instance_name      = "analytics"                # CHANGE THIS to your existing instance name!

  # Map of materialize instances for for_each loops
  # MIGRATION: If you have multiple instances, add them here
  materialize_instances = {
    (local.materialize_instance_name) = {
      namespace = local.materialize_instance_namespace
    }
  }

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
      effect = "NO_SCHEDULE"
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

# -----------------------------------------------------------------------------
# Random Resources
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
