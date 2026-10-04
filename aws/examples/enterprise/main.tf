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
  lazy_load        = true
}

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
}

# 2.0 Install the monitoring namespace and CRDs before anything that ships a
# ServiceMonitor, or that install fails or silently drops the monitor.
# Components gate their monitor on `crds_installed`, which also orders them
# after the CRDs. The namespace is created even without observability.
module "monitoring_crds" {
  source = "../../../kubernetes/modules/monitoring-crds"

  namespace    = local.monitoring_namespace
  install_crds = var.enable_observability

  depends_on = [module.eks]
}

# Upgrade path: these resources used to live in the operator and monitoring
# modules. Without the namespace move, Terraform would destroy the monitoring
# namespace and everything in it.
moved {
  from = module.operator.kubernetes_namespace.monitoring[0]
  to   = module.monitoring_crds.kubernetes_namespace.monitoring[0]
}

moved {
  from = module.monitoring[0].module.monitoring.helm_release.crds[0]
  to   = module.monitoring_crds.helm_release.crds[0]
}

# 2.1 Install VPC CNI with Network Policy support. Must come before any node
# group: EKS module v21+ clusters have no default CNI, so nodes never get Ready.
module "vpc_cni" {
  source = "../../modules/vpc-cni"

  name_prefix       = var.name_prefix
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer_url   = module.eks.cluster_oidc_issuer_url
  kubeconfig_data   = local.kubeconfig_data

  enable_network_policy    = true
  enable_policy_event_logs = true

  tags = var.tags

  depends_on = [module.eks]
}

# 2.1.1 Create base node group for Karpenter and coredns
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
  aws_region                        = var.aws_region
  aws_profile                       = var.aws_profile
  # Resolved at the root so they are known at plan time; the depends_on below
  # would defer the module's own lookups (see its `partition` variable).
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
  tags       = var.tags

  depends_on = [module.vpc_cni]
}

module "coredns" {
  source = "../../../kubernetes/modules/coredns"

  node_selector = local.base_node_labels
  # EKS has no kube-dns autoscaler deployment to scale down.
  disable_default_coredns_autoscaler = false
  # EKS module v21+ clusters have no default CoreDNS, so the service account and
  # kube-dns Service are managed here. Clusters created with v20 or earlier must
  # import their existing kube-dns Service first:
  #   terraform import 'module.coredns.kubernetes_service.kube_dns[0]' kube-system/kube-dns
  create_coredns_service_account = true
  create_kube_dns_service        = true
  kube_dns_service_cluster_ip    = cidrhost(module.eks.cluster_service_cidr, 10)
  kubeconfig_data                = local.kubeconfig_data
  cluster_identifier             = module.eks.cluster_name
  # Resolve the Polis FQDN to its internal service in-cluster (hairpin fix).
  # Built here, not from module.ory, to avoid a cycle: ory depends on coredns.
  extra_rewrites = var.enable_polis ? [{
    from = var.ory_polis_fqdn
    to   = "polis-internal.${local.ory_namespace}.svc.cluster.local"
  }] : []

  depends_on = [
    module.base_node_group,
    module.vpc_cni,
  ]
}

# Install node-local-dns to cache DNS lookups on every node
module "node_local_dns" {
  source = "../../../kubernetes/modules/node-local-dns"

  enable_service_monitor = module.monitoring_crds.crds_installed

  # EKS assigns kube-dns the .10 address of the cluster service CIDR
  dns_server = cidrhost(module.eks.cluster_service_cidr, 10)

  depends_on = [
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

  depends_on = [module.base_node_group]
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

  # Wait for the Karpenter helm release that installs the EC2NodeClass CRD.
  depends_on = [module.karpenter]
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
  subnet_ids         = module.networking.private_subnet_ids
  swap_enabled       = true
  tags               = var.tags

  # See note on ec2nodeclass_generic.
  depends_on = [module.karpenter]
}

module "nodepool_materialize" {
  source = "../../modules/karpenter-nodepool"

  name           = local.nodeclass_name_materialize
  nodeclass_name = local.nodeclass_name_materialize
  instance_types = local.instance_types_materialize
  node_labels    = local.materialize_node_labels
  node_taints    = local.materialize_node_taints
  # WARNING: any value other than Never may cause downtime, since Karpenter
  # expires nodes even when pods are marked do-not-disrupt. If you set one, roll
  # nodes gracefully: cordon the node, roll out every Materialize instance on the
  # pool, then let it consolidate or delete it once all clusterd and environmentd
  # pods have moved off.
  expire_after = "Never"

  # WARNING: leave termination_grace_period unset. If set, Karpenter force-evicts
  # Materialize pods from drifted nodes (e.g. after an instance type change) once
  # it passes, despite karpenter.sh/do-not-disrupt. Unset, they block disruption
  # until a Materialize rollout moves them.

  kubeconfig_data = local.kubeconfig_data

  depends_on = [
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
    module.nodepool_generic,
    module.coredns,
  ]
}

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
    module.base_node_group,
    module.coredns,
  ]
}

# 5. Install Certificate Manager for TLS
module "cert_manager" {
  source = "../../../kubernetes/modules/cert-manager"

  enable_service_monitor = module.monitoring_crds.crds_installed

  node_selector = local.generic_node_labels

  # Wait for the AWS LBC; its MutatingWebhookConfiguration intercepts every
  # Service create, so anything creating a Service first fails the webhook.
  depends_on = [
    module.eks,
    module.nodepool_generic,
    module.coredns,
    module.aws_lbc,
  ]
}

# Self-signed ClusterIssuer for the internal mTLS cert (*.cluster.local SANs,
# which public ACME issuers reject) and the browser-facing cert fallback.
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

  # Tolerations and node selector for Materialize instance workloads
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

resource "random_password" "ory_database_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# 7. Setup dedicated database instance for Materialize
module "database" {
  source                    = "../../modules/database"
  name_prefix               = var.name_prefix
  postgres_version          = "18"
  backup_retention_period   = 35
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

# Separate RDS instance for Ory Kratos
module "ory_kratos_database" {
  source                    = "../../modules/database"
  name_prefix               = "${var.name_prefix}-ory-kratos"
  postgres_version          = "18"
  backup_retention_period   = 35
  instance_class            = "db.t3.small"
  allocated_storage         = 20
  max_allocated_storage     = 50
  database_name             = "kratos"
  database_username         = "oryadmin"
  database_password         = random_password.ory_database_password.result
  multi_az                  = false
  database_subnet_ids       = module.networking.private_subnet_ids
  vpc_id                    = module.networking.vpc_id
  cluster_name              = module.eks.cluster_name
  cluster_security_group_id = module.eks.cluster_security_group_id
  node_security_group_id    = module.eks.node_security_group_id

  tags = var.tags
}

# Separate RDS instance for Ory Hydra
module "ory_hydra_database" {
  source                    = "../../modules/database"
  name_prefix               = "${var.name_prefix}-ory-hydra"
  postgres_version          = "18"
  backup_retention_period   = 35
  instance_class            = "db.t3.small"
  allocated_storage         = 20
  max_allocated_storage     = 50
  database_name             = "hydra"
  database_username         = "oryadmin"
  database_password         = random_password.ory_database_password.result
  multi_az                  = false
  database_subnet_ids       = module.networking.private_subnet_ids
  vpc_id                    = module.networking.vpc_id
  cluster_name              = module.eks.cluster_name
  cluster_security_group_id = module.eks.cluster_security_group_id
  node_security_group_id    = module.eks.node_security_group_id

  tags = var.tags
}

# Separate RDS instance for Ory Polis (one-DB-per-instance).
module "ory_polis_database" {
  count  = var.enable_polis ? 1 : 0
  source = "../../modules/database"

  name_prefix               = "${var.name_prefix}-ory-polis"
  postgres_version          = "18"
  backup_retention_period   = 35
  instance_class            = "db.t3.small"
  allocated_storage         = 20
  max_allocated_storage     = 50
  database_name             = "polis"
  database_username         = "oryadmin"
  database_password         = random_password.ory_database_password.result
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
  source               = "../../modules/storage"
  name_prefix          = var.name_prefix
  bucket_force_destroy = true

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
locals {
  # The OIDC provider Materialize trusts. var.direct_oidc, when set, keeps an
  # existing provider authoritative while Ory runs beside it; clearing it cuts over.
  materialize_oidc_parameters = var.direct_oidc != null ? {
    oidc_issuer               = var.direct_oidc.issuer
    oidc_audience             = jsonencode(var.direct_oidc.audience)
    oidc_authentication_claim = var.direct_oidc.authentication_claim
    console_oidc_client_id    = var.direct_oidc.console_client_id
    console_oidc_scopes       = var.direct_oidc.scopes
    } : {
    oidc_issuer                  = module.ory.hydra_external_url
    oidc_audience                = jsonencode([module.ory.oauth2_client_id])
    oidc_authentication_claim    = "email"
    console_oidc_client_id       = module.ory.oauth2_client_id
    console_oidc_scopes          = "openid email"
    oidc_group_role_sync_enabled = "true"
  }
}

module "materialize_instance" {
  source               = "../../../kubernetes/modules/materialize-instance"
  environmentd_version = var.materialize_version
  instance_name        = local.materialize_instance_name
  instance_namespace   = local.materialize_instance_namespace
  metadata_backend_url = local.metadata_backend_url
  persist_backend_url  = local.persist_backend_url

  enable_network_policies = true
  monitoring_namespace    = local.monitoring_namespace

  force_rollout   = var.force_rollout
  request_rollout = var.request_rollout

  # OIDC login (Ory, or var.direct_oidc when set). mz_system keeps a password
  # login as the admin fallback.
  external_login_password_mz_system = random_password.external_login_password_mz_system.result
  authenticator_kind                = "Oidc"

  # IRSA role for S3 access
  service_account_annotations = {
    "eks.amazonaws.com/role-arn" = module.storage.materialize_s3_role_arn
  }

  license_key = var.license_key

  issuer_ref = local.cert_issuer
  # Internal mTLS has cluster.local SANs which public ACME issuers can't sign,
  # so always route the internal cert spec through the self-signed cluster issuer.
  internal_issuer_ref = {
    name = module.self_signed_cluster_issuer.issuer_name
    kind = "ClusterIssuer"
  }

  # Browser-facing SANs. balancerd is reached from the console JS in the
  # browser, so it also needs a publicly trusted cert + DNS record.
  console_extra_dns_names   = [var.materialize_console_fqdn]
  balancerd_extra_dns_names = [var.materialize_balancerd_fqdn]

  # With Ory, the client ID is the UUID Hydra Maester generates. Other settable parameters:
  # https://materialize.com/docs/sql/alter-system-set/#key-configuration-parameters
  system_parameters = local.materialize_oidc_parameters

  # Wire the materialize -> ory NetworkPolicy.
  ory_namespace = local.ory_namespace

  depends_on = [
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
  # Used in the telemetry bucket names. Resolved here because the depends_on
  # below would defer a lookup in the module to apply time and plan a bucket replacement.
  account_id = data.aws_caller_identity.current.account_id

  # Loki and Thanos write right away and S3 will not delete a non-empty bucket,
  # so without this `terraform destroy` hangs. Set to false for data you need to keep.
  bucket_force_destroy = true

  namespace = module.monitoring_crds.namespace
  # module.monitoring_crds already creates the namespace and CRDs.
  create_namespace       = false
  enable_monitoring_crds = false

  oidc_provider_arn       = module.eks.oidc_provider_arn
  cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url

  node_selector = local.generic_node_labels
  storage_class = module.ebs_csi_driver.storage_class_name

  # Optional Datadog or OTLP (Honeycomb, Grafana Cloud, your own collector) export.
  # Each needs a credential: declare it as a `sensitive` variable of your own and
  # set it via terraform.tfvars or TF_VAR_*, never as a literal. The module keeps
  # it in a Secret and rolls the gateway when it changes.
  #
  # datadog_metrics = { site = "datadoghq.com" }
  # datadog_api_key = var.datadog_api_key
  #
  # otlp_metrics = {
  #   url          = "api.honeycomb.io"
  #   auth_headers = { "x-honeycomb-dataset" = "mzmon" }
  # }
  # otlp_auth_header_secrets = { "x-honeycomb-team" = var.honeycomb_api_key }

  # Alert receivers. None is configured by default, so alerts reach nobody until
  # you set one. Receivers read credentials from files that
  # `alerting_receiver_secrets` supplies as a Secret; declare them `sensitive` too.
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

  materialize_instance_namespace = local.materialize_instance_namespace
  materialize_operator_namespace = local.operator_namespace

  # Grafana gets its own RDS instance: RDS has no API to add a database to an
  # existing instance, so it cannot share `module.database`.
  grafana_database = {
    vpc_id                    = module.networking.vpc_id
    subnet_ids                = module.networking.private_subnet_ids
    cluster_name              = module.eks.cluster_name
    cluster_security_group_id = module.eks.cluster_security_group_id
    node_security_group_id    = module.eks.node_security_group_id

    # Unlike the `simple` example, keep a final snapshot on destroy: it holds
    # Grafana's service-account tokens and alert rules.
    skip_final_snapshot = false
  }

  # The monitoring module refuses a public Grafana with an unrestricted allowlist;
  # `grafana_allow_public_access` is the opt-in that lifts it.
  additional_values = var.grafana_allow_public_access ? [
    yamlencode({ connections = { grafana = { allowPublicAccess = true } } })
  ] : []

  # NLB owned by the monitoring module. The Service stays ClusterIP behind a
  # TargetGroupBinding, so the allowlist is security-group rules on the NLB.
  grafana_load_balancer = {
    vpc_id                 = module.networking.vpc_id
    subnet_ids             = var.internal_load_balancer ? module.networking.private_subnet_ids : module.networking.public_subnet_ids
    node_security_group_id = module.eks.node_security_group_id
    ingress_cidr_blocks    = var.ingress_cidr_blocks

    internal = var.internal_load_balancer
    host     = var.grafana_host
  }

  tags = var.tags

  # No issuer is set on purpose, so the chart bootstraps a self-signed CA scoped to
  # the monitoring release. Its components have no per-client authorization, so a
  # shared cluster issuer would trust any certificate holder; set
  # `internal_issuer_ref` only knowingly. `issuer_ref` (browser-facing) needs
  # `grafana_external_dns_names` and Grafana serving HTTPS, which these examples
  # do not do yet.

  depends_on = [
    # The chart renders Certificates, so the cert-manager CRDs must exist first.
    module.cert_manager,
    module.operator,
    module.nodepool_generic,
    module.coredns,
    module.ebs_csi_driver,
  ]
}

# 11. Setup dedicated NLB for Materialize instance
module "materialize_nlb" {
  source = "../../modules/nlb"

  instance_name                    = local.materialize_instance_name
  name_prefix                      = var.name_prefix
  namespace                        = local.materialize_instance_namespace
  subnet_ids                       = var.internal_load_balancer ? module.networking.private_subnet_ids : module.networking.public_subnet_ids
  internal                         = var.internal_load_balancer
  enable_cross_zone_load_balancing = true
  vpc_id                           = module.networking.vpc_id
  mz_resource_id                   = module.materialize_instance.instance_resource_id
  node_security_group_id           = module.eks.node_security_group_id
  ingress_cidr_blocks              = var.ingress_cidr_blocks

  # Console on 443 so OIDC redirects to https://<materialize_console_fqdn>/auth/callback
  # need no :8080 suffix and match Hydra's CORS origins. Pods still listen on 8080.
  console_listener_port = 443

  tags = var.tags
}

# Ory stack (Kratos, Hydra, selfservice UI, Materialize bridge). This example
# passes the cloud-specific inputs and reads back the OIDC issuer and client ID.
module "ory" {
  source = "../../../kubernetes/modules/ory-stack"

  enable_service_monitors = var.enable_ory_service_monitors && module.monitoring_crds.crds_installed
  monitoring_namespace    = module.monitoring_crds.namespace

  namespace = local.ory_namespace

  hydra_fqdn  = var.ory_hydra_fqdn
  kratos_fqdn = var.ory_kratos_fqdn
  ui_fqdn     = var.ory_ui_fqdn

  kratos_dsn = local.ory_kratos_dsn
  hydra_dsn  = local.ory_hydra_dsn

  # Polis (SAML-to-OIDC bridge). Off by default. Its chart and image come through
  # the OEL registry proxy using the license key, so no extra credential is needed.
  enable_polis = var.enable_polis
  polis_fqdn   = var.enable_polis ? var.ory_polis_fqdn : null
  polis_dsn    = local.ory_polis_dsn

  polis_helm_values = var.polis_helm_values

  oel_registry    = var.ory_oel_registry
  oel_image_tag   = var.ory_oel_image_tag
  license_key_jwt = var.license_key

  cert_issuer_ref                 = local.cert_issuer
  cert_issuer_signs_cluster_local = var.cert_issuer_ref == null

  # Materialize integration: OAuth2 client CRD and ory-side ingress NetworkPolicy.
  materialize_namespace    = local.materialize_instance_namespace
  materialize_console_fqdn = var.materialize_console_fqdn

  # AWS LBC settings: load_balancer_class routes the Service through the LBC,
  # externalTrafficPolicy = Local preserves client source IPs through the NLB.
  lb_annotations             = local.ory_lb_annotations
  lb_load_balancer_class     = "service.k8s.aws/nlb"
  lb_external_traffic_policy = "Local"

  # Firewall the public Ory NLBs like the Materialize ones. The LBC turns
  # loadBalancerSourceRanges into the NLB security group's inbound rules.
  lb_overrides = var.internal_load_balancer || local.ory_lb_source_ranges == null ? {} : {
    for role in ["hydra", "kratos", "ui", "polis"] : role => {
      source_ranges = role == "polis" ? concat(local.ory_lb_source_ranges, local.okta_scim_source_ranges) : local.ory_lb_source_ranges
    }
  }

  node_selector = local.generic_node_labels

  upstream_identity_providers = var.upstream_identity_providers
  # The SAML IdP metadata lives in idp-metadata.xml rather than inline in
  # tfvars; inject it into each SAML provider here.
  saml_providers = [
    for p in var.saml_providers : merge(p, {
      raw_idp_metadata_xml = file("${path.module}/idp-metadata.xml")
    })
  ]

  depends_on = [
    module.coredns,
    module.aws_lbc,
  ]
}

# Upgrade path: this NetworkPolicy moved from ory-stack to materialize-instance.
# The old ory-stack console LoadBalancer is destroyed on apply, and the console
# listener on module.materialize_nlb moves from 8080 to 443 (same NLB DNS name).
moved {
  from = module.ory.kubernetes_network_policy_v1.materialize_to_ory_egress[0]
  to   = module.materialize_instance.kubernetes_network_policy_v1.allow_ory_egress[0]
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

  # Ory database DSNs
  ory_kratos_dsn = format(
    "postgres://%s:%s@%s/%s?sslmode=require",
    module.ory_kratos_database.db_instance_username,
    urlencode(random_password.ory_database_password.result),
    module.ory_kratos_database.db_instance_endpoint,
    "kratos"
  )

  ory_hydra_dsn = format(
    "postgres://%s:%s@%s/%s?sslmode=require",
    module.ory_hydra_database.db_instance_username,
    urlencode(random_password.ory_database_password.result),
    module.ory_hydra_database.db_instance_endpoint,
    "hydra"
  )

  # uselibpqcompat=true keeps sslmode=require at libpq semantics (encrypt, don't verify).
  ory_polis_dsn = var.enable_polis ? format(
    "postgres://%s:%s@%s/%s?sslmode=require&uselibpqcompat=true",
    module.ory_polis_database[0].db_instance_username,
    urlencode(random_password.ory_database_password.result),
    module.ory_polis_database[0].db_instance_endpoint,
    "polis"
  ) : null

  ory_namespace = "ory"

  # cert-manager ClusterIssuer for browser-facing TLS. Defaults to the built-in
  # self-signed issuer; override via var.cert_issuer_ref to plug in a real one.
  cert_issuer = var.cert_issuer_ref != null ? var.cert_issuer_ref : {
    name = module.self_signed_cluster_issuer.issuer_name
    kind = "ClusterIssuer"
  }

  # Sources allowed through the public Ory NLBs: ingress_cidr_blocks plus the
  # cluster itself. Pods that call the Ory hostnames reach these NLBs from
  # the VPC, and an internet-facing NLB sees them as the NAT gateways' public
  # IPs. A null ingress_cidr_blocks leaves the NLBs unrestricted.
  ory_lb_source_ranges = var.ingress_cidr_blocks == null ? null : concat(
    var.ingress_cidr_blocks,
    [for ip in module.networking.nat_public_ips : "${ip}/32"],
    [module.networking.vpc_cidr_block],
  )

  # Okta's SCIM egress ranges, written by scripts/update-okta-ip-ranges.sh.
  # Okta pushes SCIM to Polis from its own cloud, so Polis admits them too.
  okta_scim_source_ranges = fileexists("${path.module}/okta-scim-source-ranges.json") ? jsondecode(file("${path.module}/okta-scim-source-ranges.json")) : []

  # AWS LBC annotations for the Ory NLBs.
  ory_lb_annotations = merge(
    {
      "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
      "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
      "service.beta.kubernetes.io/aws-load-balancer-scheme"          = var.internal_load_balancer ? "internal" : "internet-facing"
    },
    var.internal_load_balancer ? {} : {
      "service.beta.kubernetes.io/aws-load-balancer-ip-address-type" = "ipv4"
    },
  )

}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
