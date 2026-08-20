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

# lazy_load = true lets alekc/kubectl v2.4.0+ defer kubeconfig resolution
# (which is strict at provider-configure since v2.3.0) until first use. Without
# it, same-root cluster-plus-manifests applies fail at plan with an empty REST
# config because module.eks outputs are unknown before the cluster exists. See:
# https://registry.terraform.io/providers/alekc/kubectl/latest/docs#troubleshooting
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

# ==============================================================================
# Multi-AZ Network Topology
# ==============================================================================
# This configuration creates a VPC with subnets distributed across 3 availability
# zones for high availability:
#
# - Private subnets (10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24): One per AZ, used for
#   EKS nodes, Materialize workloads, and RDS. Traffic egresses via NAT gateway(s).
#
# - Public subnets (10.0.101.0/24, 10.0.102.0/24, 10.0.103.0/24): One per AZ, used
#   for NAT gateways and public-facing load balancers.
#
# The availability_zones list determines the number of AZs used. Each element must
# have a corresponding CIDR block in private_subnet_cidrs and public_subnet_cidrs.
#
# NAT Gateway Options (via single_nat_gateway variable in networking module):
# - single_nat_gateway = true (default): One NAT gateway for all AZs. Lower cost
#   but creates a single point of failure and cross-AZ traffic charges.
# - single_nat_gateway = false: One NAT gateway per AZ. Higher availability and
#   keeps traffic within each AZ, but increases cost.
# ==============================================================================

# 1. Create network infrastructure
module "networking" {
  source      = "../../modules/networking"
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
  cluster_version                          = "1.34"
  vpc_id                                   = module.networking.vpc_id
  private_subnet_ids                       = module.networking.private_subnet_ids
  cluster_enabled_log_types                = ["api", "audit"]
  enable_cluster_creator_admin_permissions = true
  materialize_node_ingress_cidrs           = [module.networking.vpc_cidr_block]
  k8s_apiserver_authorized_networks        = var.k8s_apiserver_authorized_networks
  tags                                     = var.tags


  depends_on = [
    module.networking,
  ]
}

# ==============================================================================
# Multi-AZ Node Distribution
# ==============================================================================
# The base node group uses subnet_ids from all private subnets, enabling EKS to
# distribute nodes across all configured availability zones. This ensures:
# - Karpenter controller pods can survive an AZ failure
# - CoreDNS replicas are spread for DNS high availability
# - System workloads remain available during zone outages
# ==============================================================================

# 2.1 Create base node group for Karpenter and coredns
module "base_node_group" {
  source = "../../modules/eks-node-group"

  cluster_name                      = module.eks.cluster_name
  subnet_ids                        = module.networking.private_subnet_ids # Spans all AZs
  node_group_name                   = "${var.name_prefix}-base"
  instance_types                    = local.instance_types_base
  swap_enabled                      = false
  min_size                          = 2
  max_size                          = 3
  desired_size                      = 2
  labels                            = local.base_node_labels
  cluster_service_cidr              = module.eks.cluster_service_cidr
  cluster_primary_security_group_id = module.eks.node_security_group_id
  aws_region                        = var.aws_region
  aws_profile                       = var.aws_profile
  tags                              = var.tags
}

# 2.1.1 Install VPC CNI with Network Policy support
module "vpc_cni" {
  source = "../../modules/vpc-cni"

  name_prefix       = var.name_prefix
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer_url   = module.eks.cluster_oidc_issuer_url

  enable_network_policy    = true
  enable_policy_event_logs = true

  kubeconfig_data = local.kubeconfig_data

  tags = var.tags

  depends_on = [
    module.eks,
    module.base_node_group,
  ]
}

module "coredns" {
  source = "../../../kubernetes/modules/coredns"

  node_selector = local.base_node_labels
  # in aws coredns autoscaler deployment doesn't exist
  disable_default_coredns_autoscaler = false
  kubeconfig_data                    = local.kubeconfig_data
  cluster_identifier                 = module.eks.cluster_name

  depends_on = [
    module.eks,
    module.base_node_group,
    module.networking,
    module.vpc_cni,
  ]
}

# 2.1.3 Install node-local-dns to cache DNS lookups on every node
module "node_local_dns" {
  source = "../../../kubernetes/modules/node-local-dns"

  # EKS assigns kube-dns the .10 address of the cluster service CIDR
  dns_server = cidrhost(module.eks.cluster_service_cidr, 10)

  depends_on = [
    module.eks,
    module.base_node_group,
    module.coredns,
  ]
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
  tags                    = var.tags

  depends_on = [
    module.eks,
    module.base_node_group,
    module.networking,
  ]
}

# ==============================================================================
# Karpenter Multi-AZ Provisioning
# ==============================================================================
# EC2NodeClasses define where Karpenter can launch nodes. By passing all private
# subnet IDs, Karpenter can provision nodes in any availability zone based on:
# - Pod topology spread constraints
# - Instance type availability per zone
# - Zone-specific capacity
#
# Karpenter automatically selects the optimal zone for each node based on the
# pending pod's requirements and available capacity.
# ==============================================================================

# Create a generic nodeclass and nodepool for all workloads except Materialize.
module "ec2nodeclass_generic" {
  source = "../../modules/karpenter-ec2nodeclass"

  name               = local.nodeclass_name_generic
  ami_selector_terms = local.ami_selector_terms
  instance_types     = local.instance_types_generic
  instance_profile   = module.karpenter.node_instance_profile
  security_group_ids = [module.eks.node_security_group_id]
  subnet_ids         = module.networking.private_subnet_ids # Enables multi-AZ provisioning
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

  # Generic workloads can tolerate eviction, so cap how long draining
  # pods can delay node replacement.
  termination_grace_period = "300s"

  kubeconfig_data = local.kubeconfig_data

  depends_on = [
    module.karpenter,
    module.ec2nodeclass_generic,
    module.coredns,
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
  subnet_ids         = module.networking.private_subnet_ids # Enables multi-AZ provisioning
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
  # WARNING: setting this to any value other than Never may cause
  # downtime. Karpenter will remove nodes regardless of whether they
  # have pods with do-not-disrupt labels. If you set this to any duration
  # you should ensure that you always gracefully roll nodes during a
  # materialize rollout. To do this cordon the node, perform an upgrade or 
  # forced rollout of all materialize instances that may be using the node pool.
  # the node should have all pods removed from it and be consolidated. You may
  # also delete the node after all clusterd and environmentd pods have been moved off.
  expire_after = "Never"

  # WARNING: leave termination_grace_period unset here. If set, Karpenter
  # will replace drifted nodes (e.g. after an instance type change) even
  # though Materialize pods carry the karpenter.sh/do-not-disrupt
  # annotation, force-evicting them once the deadline passes. Unset, those
  # pods block disruption until a Materialize rollout moves them.

  kubeconfig_data = local.kubeconfig_data

  depends_on = [
    module.karpenter,
    module.ec2nodeclass_materialize,
    module.coredns,
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
    module.coredns,
  ]
}

# ==============================================================================
# EBS CSI Driver - Zone-Aware Storage
# ==============================================================================
# The EBS CSI driver creates a gp3 StorageClass with WaitForFirstConsumer binding
# mode. This ensures EBS volumes are provisioned in the same availability zone as
# the pod that will use them, avoiding cross-AZ volume attachment failures.
#
# When a PVC is created, the volume is not provisioned until a pod references it.
# At that point, the scheduler picks a node (and thus an AZ), and the EBS volume
# is created in that same AZ.
# ==============================================================================

# 4. Install EBS CSI Driver for dynamic EBS volume provisioning
module "ebs_csi_driver" {
  source = "../../modules/ebs-csi-driver"

  name_prefix       = var.name_prefix
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer_url   = module.eks.cluster_oidc_issuer_url
  node_selector     = local.generic_node_labels

  tags = var.tags

  depends_on = [
    module.eks,
    module.base_node_group,
    module.coredns,
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
    module.coredns,
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

  operator_version = var.materialize_version

  name_prefix    = var.name_prefix
  aws_region     = var.aws_region
  aws_account_id = data.aws_caller_identity.current.account_id

  # tolerations and node selector for all mz instance workloads on AWS
  instance_pod_tolerations = local.materialize_tolerations
  instance_node_selector   = local.materialize_node_labels

  # node selector for operator and metrics-server workloads
  operator_node_selector = local.generic_node_labels

  enable_network_policies = true
  operator_namespace      = local.operator_namespace
  monitoring_namespace    = local.monitoring_namespace

  # Enable Prometheus scrape annotations when observability is enabled
  helm_values = var.enable_observability ? {
    observability = {
      enabled = true
      prometheus = {
        scrapeAnnotations = {
          enabled = true
        }
      }
    }
  } : {}

  depends_on = [
    module.eks,
    module.networking,
    module.nodepool_generic,
    module.coredns,
    module.vpc_cni,
    module.cert_manager,
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

# ==============================================================================
# RDS Database - Multi-AZ Considerations
# ==============================================================================
# The database uses multi_az = false by default for cost savings in development/
# test environments. For production deployments, set multi_az = true to enable:
# - Synchronous standby replica in a different AZ
# - Automatic failover during AZ outages or maintenance
# - Enhanced durability with synchronous replication
#
# The database_subnet_ids span all AZs, allowing RDS to place the primary and
# standby (if multi_az = true) in different availability zones.
# ==============================================================================

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
  multi_az                  = false # Set to true for production HA
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

  # For testing purposes, we are disabling versioning to allow for easier cleanup.
  # SSE-S3 encryption remains enabled by default for this example.
  enable_bucket_versioning = false
  enable_bucket_encryption = true

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
  environmentd_version = var.materialize_version
  instance_name        = local.materialize_instance_name
  instance_namespace   = local.materialize_instance_namespace
  metadata_backend_url = local.metadata_backend_url
  persist_backend_url  = local.persist_backend_url

  enable_network_policies = true
  monitoring_namespace    = local.monitoring_namespace

  # Rollout configuration
  force_rollout   = var.force_rollout
  request_rollout = var.request_rollout

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

  # System parameters for the Materialize instance
  # See: https://materialize.com/docs/self-managed-deployments/configuration-system-parameters/
  # Example settings:
  #   max_connections               = "1000"
  #   allowed_cluster_replica_sizes = "'25cc', '50cc', '100cc', '200cc', '400cc', '800cc', '1600cc', '3200cc'"
  #   max_clusters                  = "10"
  #   max_sources                   = "50"
  #   max_sinks                     = "50"
  system_parameters = {}

  depends_on = [
    module.eks,
    module.database,
    module.storage,
    module.networking,
    module.self_signed_cluster_issuer,
    module.operator,
    module.aws_lbc,
    module.nodepool_materialize,
    module.coredns,
  ]
}

# 10. Setup Observability Stack (Grafana, Loki, Thanos, Alloy)
module "monitoring" {
  count  = var.enable_observability ? 1 : 0
  source = "../../modules/monitoring"

  name_prefix = var.name_prefix
  region      = var.aws_region

  # Matches what these examples already pass to `module.storage`. Loki and
  # Thanos start writing immediately, and neither S3 nor GCS will delete a
  # non-empty bucket, so without this `terraform destroy` wedges on the
  # telemetry buckets. Set to false for anything you cannot afford to lose.
  bucket_force_destroy = true

  namespace = local.monitoring_namespace
  # The operator module creates the "monitoring" namespace.
  create_namespace = false

  oidc_provider_arn       = module.eks.oidc_provider_arn
  cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url

  node_selector = local.generic_node_labels
  storage_class = module.ebs_csi_driver.storage_class_name

  # Datadog and generic OTLP (Honeycomb, Grafana Cloud, your own collector) fan
  # out the same way, and need no cloud resources — so they are set here rather
  # than behind an `enable_*` toggle. Commented out because both need a
  # credential; the module puts it in a Secret rather than the Helm values, and
  # rolls the gateway when it changes.
  #
  # Declare the two credentials as `sensitive` variables of your own before
  # uncommenting — this example does not, and they belong in `terraform.tfvars`
  # or `TF_VAR_*` rather than as literals in a file you commit.
  #
  # datadog_metrics = { site = "datadoghq.com" }
  # datadog_api_key = var.datadog_api_key
  #
  # otlp_metrics = {
  #   url          = "api.honeycomb.io"
  #   auth_headers = { "x-honeycomb-dataset" = "mzmon" }
  # }
  # otlp_auth_header_secrets = { "x-honeycomb-team" = var.honeycomb_api_key }

  materialize_instance_namespace = local.materialize_instance_namespace
  materialize_operator_namespace = local.operator_namespace

  # A dedicated RDS instance for Grafana's own state, so dashboards and API
  # tokens created in the UI survive a pod restart. RDS has no API for adding a
  # database to an existing instance, so this is separate from `module.database`
  # rather than a second database inside it.
  #
  # `skip_final_snapshot` stays at the module default (true) here, matching this
  # example's throwaway posture — the same reason `bucket_force_destroy` is on
  # and bucket versioning is off.
  grafana_database = {
    vpc_id                    = module.networking.vpc_id
    subnet_ids                = module.networking.private_subnet_ids
    cluster_name              = module.eks.cluster_name
    cluster_security_group_id = module.eks.cluster_security_group_id
    node_security_group_id    = module.eks.node_security_group_id
  }

  # Off by default: the monitoring module refuses a public Grafana with an
  # unrestricted allowlist, and this is the acknowledgement that lifts it.
  # See `grafana_allow_public_access`.
  additional_values = var.grafana_allow_public_access ? [
    yamlencode({ connections = { grafana = { allowPublicAccess = true } } })
  ] : []

  # An NLB this module creates and owns — see `grafana_load_balancer`. The Service
  # stays ClusterIP; a TargetGroupBinding attaches the target group to it, and the
  # allowlist is security-group rules on the NLB rather than the Service.
  grafana_load_balancer = {
    vpc_id                 = module.networking.vpc_id
    subnet_ids             = var.internal_load_balancer ? module.networking.private_subnet_ids : module.networking.public_subnet_ids
    node_security_group_id = module.eks.node_security_group_id
    ingress_cidr_blocks    = var.ingress_cidr_blocks

    internal = var.internal_load_balancer
    host     = var.grafana_host
  }

  tags = var.tags

  depends_on = [
    module.operator,
    module.nodepool_generic,
    module.coredns,
    module.ebs_csi_driver,
  ]
}

# ==============================================================================
# Network Load Balancer - Cross-Zone Load Balancing
# ==============================================================================
# The NLB is deployed across all subnets (private or public depending on
# internal_load_balancer setting). Cross-zone load balancing is enabled by
# default, which:
# - Distributes traffic evenly across all healthy targets in all AZs
# - Improves availability when target capacity is uneven across zones
# - Note: Cross-zone traffic incurs inter-AZ data transfer charges
#
# For cost optimization with balanced target distribution, you can disable
# cross-zone load balancing, but this may cause uneven load if AZ capacity
# differs.
# ==============================================================================

# 11. Setup dedicated NLB for Materialize instance
module "materialize_nlb" {
  source = "../../modules/nlb"

  instance_name                    = local.materialize_instance_name
  name_prefix                      = var.name_prefix
  namespace                        = local.materialize_instance_namespace
  subnet_ids                       = var.internal_load_balancer ? module.networking.private_subnet_ids : module.networking.public_subnet_ids
  internal                         = var.internal_load_balancer
  enable_cross_zone_load_balancing = true # Ensures even traffic distribution across AZs
  vpc_id                           = module.networking.vpc_id
  mz_resource_id                   = module.materialize_instance.instance_resource_id
  node_security_group_id           = module.eks.node_security_group_id
  ingress_cidr_blocks              = var.ingress_cidr_blocks

  tags = var.tags

  depends_on = [
    module.materialize_instance
  ]
}

locals {
  materialize_instance_namespace = "materialize-environment"
  operator_namespace             = "materialize"
  materialize_instance_name      = "main"

  monitoring_namespace = "monitoring"

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
