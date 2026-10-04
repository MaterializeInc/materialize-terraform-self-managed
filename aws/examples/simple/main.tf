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

# lazy_load defers kubeconfig resolution to first use. Without it, plan fails
# with an empty REST config while module.eks outputs are still unknown. See:
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
# One private subnet (EKS nodes, Materialize, RDS; egress via NAT) and one public
# subnet (NAT gateways, public load balancers) per AZ. Each AZ needs a CIDR in
# both subnet lists. The networking module's single_nat_gateway defaults to true:
# cheaper, but a single point of failure with cross-AZ traffic charges. Set it
# to false for one NAT gateway per AZ.
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

# 2.0 Install the monitoring namespace and CRDs before anything that ships a
# ServiceMonitor, or those charts fail or silently drop it. Components enable
# their monitors from `crds_installed`, which also orders them after the CRDs.
# The namespace is created even when observability is off.
module "monitoring_crds" {
  source = "../../../kubernetes/modules/monitoring-crds"

  namespace    = local.monitoring_namespace
  install_crds = var.enable_observability

  depends_on = [module.eks]
}

# State migration: these used to live in the operator and monitoring modules.
# Without the namespace move, Terraform destroys the monitoring namespace.
moved {
  from = module.operator.kubernetes_namespace.monitoring[0]
  to   = module.monitoring_crds.kubernetes_namespace.monitoring[0]
}

moved {
  from = module.monitoring[0].module.monitoring.helm_release.crds[0]
  to   = module.monitoring_crds.helm_release.crds[0]
}

# ==============================================================================
# Multi-AZ Node Distribution
# ==============================================================================
# The base node group spans all private subnets, so Karpenter, CoreDNS and other
# system pods are spread across AZs and survive a zone outage.
# ==============================================================================

# 2.1 Install VPC CNI with Network Policy support. Must come before any node
# group: EKS module v21+ clusters have no default CNI, so nodes cannot go Ready.
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
  ]
}

# 2.1.1 Create base node group for Karpenter and coredns
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
  # Resolved at the root so they are known at plan time; the module-level
  # depends_on would defer the module's own lookups to apply time.
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
  tags       = var.tags

  depends_on = [module.vpc_cni]
}

# 2.1.2 Install CoreDNS
module "coredns" {
  source = "../../../kubernetes/modules/coredns"

  node_selector = local.base_node_labels
  # EKS has no CoreDNS autoscaler deployment to disable
  disable_default_coredns_autoscaler = false
  # EKS module v21+ clusters have no default CoreDNS, so the service account and
  # kube-dns Service are managed here. On clusters created with v20 or earlier,
  # import the existing kube-dns Service first:
  #   terraform import 'module.coredns.kubernetes_service.kube_dns[0]' kube-system/kube-dns
  create_coredns_service_account = true
  create_kube_dns_service        = true
  kube_dns_service_cluster_ip    = cidrhost(module.eks.cluster_service_cidr, 10)
  kubeconfig_data                = local.kubeconfig_data
  cluster_identifier             = module.eks.cluster_name

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

  enable_service_monitor = module.monitoring_crds.crds_installed

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

  enable_service_monitor = module.monitoring_crds.crds_installed
  # The node pools' instance types, for Karpenter's capacity-availability metric.
  service_monitor_instance_types = distinct(concat(local.instance_types_generic, local.instance_types_materialize))

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
# The EC2NodeClasses get all private subnets, so Karpenter can launch nodes in
# any AZ, picking the zone from pod topology constraints and zone capacity.
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
  # WARNING: any value other than "Never" can cause downtime, since Karpenter
  # removes expired nodes even with do-not-disrupt pods. If you set one, roll
  # nodes gracefully: cordon the node, then upgrade or force a rollout of every
  # Materialize instance using it. Once clusterd and environmentd pods have
  # moved off, the node is consolidated, or you can delete it.
  expire_after = "Never"

  # WARNING: leave termination_grace_period unset. If set, Karpenter replaces
  # drifted nodes (e.g. after an instance type change) and force-evicts
  # do-not-disrupt Materialize pods once it expires.

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

  enable_service_monitor = module.monitoring_crds.crds_installed

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
# The driver's gp3 StorageClass uses WaitForFirstConsumer, so each volume is
# created in the AZ of the node its pod lands on, avoiding cross-AZ attach failures.
# ==============================================================================

# 4. Install EBS CSI Driver for dynamic EBS volume provisioning
module "ebs_csi_driver" {
  source = "../../modules/ebs-csi-driver"

  enable_service_monitor = module.monitoring_crds.crds_installed

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

  enable_service_monitor = module.monitoring_crds.crds_installed

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

  # module.monitoring_crds creates the monitoring namespace.
  create_monitoring_namespace           = false
  enable_metrics_server_service_monitor = module.monitoring_crds.crds_installed

  operator_version = var.materialize_version

  name_prefix    = var.name_prefix
  aws_region     = var.aws_region
  aws_account_id = data.aws_caller_identity.current.account_id

  # Tolerations and node selector for Materialize instance pods
  instance_pod_tolerations = local.materialize_tolerations
  instance_node_selector   = local.materialize_node_labels

  # node selector for operator and metrics-server workloads
  operator_node_selector = local.generic_node_labels

  enable_network_policies = true
  operator_namespace      = local.operator_namespace
  monitoring_namespace    = module.monitoring_crds.namespace

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
# multi_az = false keeps dev/test costs down. For production, set it to true for
# a synchronous standby in another AZ with automatic failover. The subnets span
# all AZs so RDS can place the primary and standby apart.
# ==============================================================================

# 7. Setup dedicated database instance for Materialize
module "database" {
  source                    = "../../modules/database"
  name_prefix               = var.name_prefix
  postgres_version          = "18"
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
  source               = "../../modules/storage"
  name_prefix          = var.name_prefix
  bucket_force_destroy = true

  # Versioning is off for easier cleanup in testing; SSE-S3 encryption stays on.
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
  # Part of the telemetry bucket names. Resolved here because the `depends_on`
  # below would defer a lookup inside the module to apply time, leaving the
  # bucket names unknown at plan and planning a bucket replacement.
  account_id = data.aws_caller_identity.current.account_id

  # Loki and Thanos write immediately and a non-empty bucket cannot be deleted,
  # so without this `terraform destroy` gets stuck. Set to false for real data.
  bucket_force_destroy = true

  namespace = module.monitoring_crds.namespace
  # module.monitoring_crds already creates the namespace and installs the CRDs.
  create_namespace       = false
  enable_monitoring_crds = false

  oidc_provider_arn       = module.eks.oidc_provider_arn
  cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url

  node_selector = local.generic_node_labels
  storage_class = module.ebs_csi_driver.storage_class_name

  # Optional Datadog and generic OTLP (Honeycomb, Grafana Cloud, your own
  # collector) destinations. Each needs a credential: declare it as a `sensitive`
  # variable set from terraform.tfvars or TF_VAR_*, never a committed literal.
  # The module keeps it in a Secret and rolls the gateway when it changes.
  #
  # datadog_metrics = { site = "datadoghq.com" }
  # datadog_api_key = var.datadog_api_key
  #
  # otlp_metrics = {
  #   url          = "api.honeycomb.io"
  #   auth_headers = { "x-honeycomb-dataset" = "mzmon" }
  # }
  # otlp_auth_header_secrets = { "x-honeycomb-team" = var.honeycomb_api_key }

  # Where alerts go. No receiver is configured by default, so alerts reach nobody
  # until one is set. Receivers read credentials by file path from the Secret
  # built from `alerting_receiver_secrets`; declare those as `sensitive` too.
  #
  # alerting = {
  #   preset = "critical-infrastructure"
  #   receivers = {
  #     oncall = {
  #       class  = "page"
  #       config = { pagerduty_configs = [{ routing_key_file = "/etc/alertmanager/secrets/alertmanager-receivers/pagerduty-key" }] }
  #     }
  #     platform = {
  #       class  = ["high", "normal"]
  #       config = { slack_configs = [{ channel = "#platform-alerts", api_url_file = "/etc/alertmanager/secrets/alertmanager-receivers/slack-url" }] }
  #     }
  #   }
  # }
  # alerting_receiver_secrets = {
  #   "pagerduty-key" = var.pagerduty_routing_key
  #   "slack-url"     = var.platform_slack_webhook
  # }

  # CloudWatch metrics for the metadata database and persist bucket, named here
  # so nothing else in the account is pulled or billed (the module adds its own
  # buckets and Grafana's database). Nodes are found by the `aws:eks:cluster-name`
  # tag. The only account-wide series is On-Demand vCPU usage, for the vCPU quota.
  provider_metrics = var.enable_provider_metrics ? {
    rds_instance_ids  = [module.database.db_instance_id]
    s3_bucket_names   = [module.storage.bucket_name]
    eks_cluster_names = [module.eks.cluster_name]
  } : null

  materialize_instance_namespace = local.materialize_instance_namespace
  materialize_operator_namespace = local.operator_namespace

  # Dedicated RDS instance so Grafana dashboards and API tokens survive a pod
  # restart. Separate from `module.database` because RDS has no API to add a
  # database to an existing instance. `skip_final_snapshot` keeps the module
  # default (true), as this example is meant to be thrown away.
  grafana_database = {
    vpc_id                    = module.networking.vpc_id
    subnet_ids                = module.networking.private_subnet_ids
    cluster_name              = module.eks.cluster_name
    cluster_security_group_id = module.eks.cluster_security_group_id
    node_security_group_id    = module.eks.node_security_group_id
  }

  # The monitoring module refuses a public Grafana with an unrestricted allowlist;
  # this opt-in lifts that. See `grafana_allow_public_access`.
  additional_values = var.grafana_allow_public_access ? [
    yamlencode({ connections = { grafana = { allowPublicAccess = true } } })
  ] : []

  # The module creates its own NLB. The Service stays ClusterIP and is attached
  # with a TargetGroupBinding; the allowlist is security group rules on the NLB.
  grafana_load_balancer = {
    vpc_id                 = module.networking.vpc_id
    subnet_ids             = var.internal_load_balancer ? module.networking.private_subnet_ids : module.networking.public_subnet_ids
    node_security_group_id = module.eks.node_security_group_id
    ingress_cidr_blocks    = var.ingress_cidr_blocks

    internal = var.internal_load_balancer
    host     = var.grafana_host
  }

  tags = var.tags

  # No issuer is set, so the chart bootstraps a self-signed CA scoped to the
  # monitoring release. Deliberate: its components have no per-client
  # authorization, so the cluster issuer would let in any certificate it signs.
  # Set `internal_issuer_ref` to share one knowingly. The browser-facing
  # `issuer_ref` needs `grafana_host`, and Grafana does not serve HTTPS here yet.

  depends_on = [
    # The stack issues Certificates by default; without this the apply can race
    # cert-manager and fail on an unknown `cert-manager.io/v1` kind.
    module.cert_manager,
    module.operator,
    module.nodepool_generic,
    module.coredns,
    module.ebs_csi_driver,
  ]
}

# ==============================================================================
# Network Load Balancer - Cross-Zone Load Balancing
# ==============================================================================
# The NLB spans all private or public subnets, per internal_load_balancer.
# Cross-zone load balancing spreads traffic evenly across AZs but adds inter-AZ
# transfer charges; disabling it saves cost but can unbalance load.
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
data "aws_partition" "current" {}
