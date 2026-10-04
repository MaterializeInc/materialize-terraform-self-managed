provider "google" {
  project        = var.project_id
  region         = var.region
  default_labels = var.labels
}

# Used by the nodepool module for autoscaled blue-green upgrade settings,
# which are not yet available in the GA google provider.
provider "google-beta" {
  project        = var.project_id
  region         = var.region
  default_labels = var.labels
}

# Configure kubernetes provider with GKE cluster credentials
data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${module.gke.cluster_endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = "https://${module.gke.cluster_endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
  }
}

provider "kubectl" {
  host                   = "https://${module.gke.cluster_endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)

  load_config_file = false
  lazy_load        = true
}

locals {

  materialize_operator_namespace = "materialize"
  materialize_instance_namespace = "materialize-environment"
  materialize_instance_name      = "main"

  # Common node scheduling configuration
  generic_node_labels = {
    "workload" = "generic"
  }

  materialize_node_labels = {
    "workload" = "materialize-instance"
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


  subnets = [
    {
      name           = "${var.name_prefix}-subnet"
      cidr           = "192.168.0.0/20"
      region         = var.region
      private_access = true
      secondary_ranges = [
        {
          range_name    = "pods"
          ip_cidr_range = "192.168.64.0/18"
        },
        {
          range_name    = "services"
          ip_cidr_range = "192.168.128.0/20"
        }
      ]
    }
  ]

  # Use the first 3 available zones for explicit multi-zone node distribution
  node_locations = slice(data.google_compute_zones.available.names, 0, min(3, length(data.google_compute_zones.available.names)))

  database_config = {
    tier = "db-custom-N4-2-4096"
    # N4 instances only support Hyperdisk Balanced, not PD_SSD.
    disk_type               = "HYPERDISK_BALANCED"
    database                = { name = "materialize", charset = "UTF8", collation = "en_US.UTF8" }
    user_name               = "materialize"
    db_version              = "POSTGRES_18"
    backup_retained_backups = 35
  }

  # Ory database configuration (separate Cloud SQL instance)
  ory_database_config = {
    tier                    = "db-f1-micro"
    user_name               = "oryadmin"
    db_version              = "POSTGRES_18"
    backup_retained_backups = 35
  }

  database_statement_timeout = "15min"

  metadata_backend_url = format(
    "postgres://%s:%s@%s/%s?sslmode=require&options=-c%%20statement_timeout%%3D%s",
    module.database.users[0].name,
    urlencode(module.database.users[0].password),
    module.database.private_ip,
    local.database_config.database.name,
    local.database_statement_timeout
  )


  encoded_endpoint = urlencode("https://storage.googleapis.com")
  encoded_secret   = urlencode(module.storage.hmac_secret)

  persist_backend_url = format(
    "s3://%s:%s@%s/materialize?endpoint=%s&region=%s",
    module.storage.hmac_access_id,
    local.encoded_secret,
    module.storage.bucket_name,
    local.encoded_endpoint,
    var.region
  )

  kubeconfig_data = jsonencode({
    apiVersion = "v1"
    kind       = "Config"
    clusters = [{
      name = module.gke.cluster_name
      cluster = {
        certificate-authority-data = module.gke.cluster_ca_certificate
        server                     = "https://${module.gke.cluster_endpoint}"
      }
    }]
    contexts = [{
      name = module.gke.cluster_name
      context = {
        cluster = module.gke.cluster_name
        user    = module.gke.cluster_name
      }
    }]
    current-context = module.gke.cluster_name
    users = [{
      name = module.gke.cluster_name
      user = {
        token : data.google_client_config.default.access_token
      }
    }]
  })
  # Not `standard-rwo`: the default C4/C4A node pools take only Hyperdisk, and
  # every default GKE class is Persistent Disk, so a PVC there would never attach.
  storage_class = kubernetes_storage_class.hyperdisk_balanced.metadata[0].name

  # Ory database DSNs
  ory_kratos_dsn = format(
    "postgres://%s:%s@%s/%s?sslmode=require",
    module.ory_database.users[0].name,
    urlencode(module.ory_database.users[0].password),
    module.ory_database.private_ip,
    "kratos"
  )

  ory_hydra_dsn = format(
    "postgres://%s:%s@%s/%s?sslmode=require",
    module.ory_database.users[0].name,
    urlencode(module.ory_database.users[0].password),
    module.ory_database.private_ip,
    "hydra"
  )

  # uselibpqcompat=true keeps sslmode=require at libpq semantics (encrypt, don't verify).
  ory_polis_dsn = format(
    "postgres://%s:%s@%s/%s?sslmode=require&uselibpqcompat=true",
    module.ory_database.users[0].name,
    urlencode(module.ory_database.users[0].password),
    module.ory_database.private_ip,
    "polis"
  )

  ory_namespace = "ory"

  # Okta's SCIM egress ranges (generate with scripts/update-okta-ip-ranges.sh),
  # plus any operator internal/VPN ranges, applied as the Polis LB allowlist.
  okta_scim_source_ranges = fileexists("${path.module}/okta-scim-source-ranges.json") ? jsondecode(file("${path.module}/okta-scim-source-ranges.json")) : []
  polis_lb_source_ranges  = concat(local.okta_scim_source_ranges, var.ory_polis_source_ranges)

  # Sources allowed through the public Ory LBs: ingress_cidr_blocks plus the
  # cluster itself. GKE serves a pod's traffic to an LB IP inside the cluster,
  # so it arrives from the node subnet or the pod and service ranges.
  ory_lb_source_ranges = concat(
    var.ingress_cidr_blocks,
    [local.subnets[0].cidr],
    [for r in local.subnets[0].secondary_ranges : r.ip_cidr_range],
  )

  # cert-manager ClusterIssuer for browser-facing TLS. Defaults to the built-in
  # self-signed issuer; override via var.cert_issuer_ref to plug in a real one.
  cert_issuer = var.cert_issuer_ref != null ? var.cert_issuer_ref : {
    name = module.self_signed_cluster_issuer.issuer_name
    kind = "ClusterIssuer"
  }

}

# Fetch available zones for explicit multi-zone cluster configuration
data "google_compute_zones" "available" {
  project = var.project_id
  region  = var.region
  status  = "UP"
}

# GKE ships no Hyperdisk class, so create one. Not the default, which would change
# provisioning for other workloads. Not gated on `enable_observability`: any PVC on
# C4/C4A pools needs it, and turning monitoring off should not remove it.
resource "kubernetes_storage_class" "hyperdisk_balanced" {
  metadata {
    name = "hyperdisk-balanced"
  }

  storage_provisioner = "pd.csi.storage.gke.io"
  parameters = {
    type = "hyperdisk-balanced"
  }

  # Late binding so the disk lands in the zone the pod is scheduled to.
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  reclaim_policy         = "Delete"

  depends_on = [module.gke]
}

# Configure networking infrastructure including VPC, subnets, and CIDR blocks
module "networking" {
  source = "../../modules/networking"

  project_id = var.project_id
  region     = var.region
  prefix     = var.name_prefix
  subnets    = local.subnets
  labels     = var.labels
}

# Set up Google Kubernetes Engine (GKE) cluster
module "gke" {
  source = "../../modules/gke"

  project_id   = var.project_id
  region       = var.region
  prefix       = var.name_prefix
  network_name = module.networking.network_name
  # Single subnet; select the right one by name if you add more.
  subnet_name                       = module.networking.subnets_names[0]
  namespace                         = local.materialize_operator_namespace
  k8s_apiserver_authorized_networks = var.k8s_apiserver_authorized_networks
  labels                            = var.labels
  datapath_provider                 = var.datapath_provider

  # Cache DNS lookups on every node. On Dataplane V2 the GKE addon is the only
  # working node-local DNS option (see the variable description in the module).
  enable_node_local_dns = true

  # Publish upgrade notifications to Pub/Sub for the node upgrade rollout
  # trigger (see the operator module below).
  enable_upgrade_notifications = var.enable_node_upgrade_rollout_trigger

  # Explicit multi-zone configuration for production HA
  node_locations = local.node_locations
}

# Install the monitoring namespace and CRDs before anything that ships a
# ServiceMonitor, or that install fails or silently drops the monitor.
# Components gate their monitor on `crds_installed`, which also orders them
# after the CRDs. The namespace is created even without observability.
module "monitoring_crds" {
  source = "../../../kubernetes/modules/monitoring-crds"

  namespace    = "monitoring"
  install_crds = var.enable_observability

  depends_on = [module.gke]
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

# Create and configure generic node pool for all workloads except Materialize
module "generic_nodepool" {
  source = "../../modules/nodepool"

  prefix                = "${var.name_prefix}-generic"
  region                = var.region
  enable_private_nodes  = true
  cluster_name          = module.gke.cluster_name
  project_id            = var.project_id
  min_nodes             = var.generic_nodepool.min_nodes
  max_nodes             = var.generic_nodepool.max_nodes
  machine_type          = var.generic_nodepool.machine_type
  disk_type             = var.generic_nodepool.disk_type
  disk_size_gb          = var.generic_nodepool.disk_size_gb
  service_account_email = module.gke.service_account_email
  labels                = local.generic_node_labels
  swap_enabled          = false
  local_ssd_count       = 0
}

# Create and configure Materialize-dedicated node pool with taints
module "materialize_nodepool" {
  source = "../../modules/nodepool"

  prefix                = "${var.name_prefix}-mz"
  region                = var.region
  enable_private_nodes  = true
  cluster_name          = module.gke.cluster_name
  project_id            = var.project_id
  min_nodes             = var.materialize_nodepool.min_nodes
  max_nodes             = var.materialize_nodepool.max_nodes
  machine_type          = var.materialize_nodepool.machine_type
  disk_type             = var.materialize_nodepool.disk_type
  disk_size_gb          = var.materialize_nodepool.disk_size_gb
  service_account_email = module.gke.service_account_email
  labels                = merge(var.labels, local.materialize_node_labels)
  # Materialize-specific taint to isolate workloads
  node_taints = local.materialize_node_taints

  swap_enabled    = var.materialize_nodepool.swap_enabled
  local_ssd_count = var.materialize_nodepool.local_ssd_count
}

# Deploy custom CoreDNS with TTL 0 (GKE's kube-dns doesn't support disabling caching)
module "coredns" {
  source                                      = "../../../kubernetes/modules/coredns"
  create_coredns_service_account              = true
  node_selector                               = local.generic_node_labels
  kubeconfig_data                             = local.kubeconfig_data
  cluster_identifier                          = module.gke.cluster_name
  coredns_deployment_to_scale_down            = "kube-dns"
  coredns_autoscaler_deployment_to_scale_down = "kube-dns-autoscaler"
  # Resolve the Polis FQDN to its internal service in-cluster (hairpin fix).
  # Built here, not from module.ory, to avoid a cycle: ory depends on coredns.
  extra_rewrites = var.enable_polis ? [{
    from = var.ory_polis_fqdn
    to   = "polis-internal.${local.ory_namespace}.svc.cluster.local"
  }] : []
  depends_on = [module.generic_nodepool]
}

resource "random_password" "external_login_password_mz_system" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Set up PostgreSQL database instance for Materialize metadata storage
module "database" {
  source = "../../modules/database"

  databases = [local.database_config.database]
  # No password given, so the module generates one.
  users = [{ name = local.database_config.user_name }]

  project_id = var.project_id
  region     = var.region
  prefix     = var.name_prefix
  network_id = module.networking.network_id

  tier                    = local.database_config.tier
  disk_type               = local.database_config.disk_type
  db_version              = local.database_config.db_version
  backup_retained_backups = local.database_config.backup_retained_backups

  labels = var.labels

  # Wait for the networking module's PSA peering; without this, Cloud SQL
  # races and fails to find a private services connection on the VPC.
  depends_on = [module.networking]
}

# Separate Cloud SQL instance for Ory (Kratos, Hydra, and Polis when enabled)
module "ory_database" {
  source = "../../modules/database"

  databases = concat(
    [
      { name = "kratos", charset = "UTF8", collation = "en_US.UTF8" },
      { name = "hydra", charset = "UTF8", collation = "en_US.UTF8" },
    ],
    var.enable_polis ? [
      { name = "polis", charset = "UTF8", collation = "en_US.UTF8" },
    ] : []
  )
  users = [{ name = local.ory_database_config.user_name }]

  project_id = var.project_id
  region     = var.region
  prefix     = "${var.name_prefix}-ory"
  network_id = module.networking.network_id

  tier                    = local.ory_database_config.tier
  db_version              = local.ory_database_config.db_version
  backup_retained_backups = local.ory_database_config.backup_retained_backups

  labels = var.labels

  # See note on module.database.
  depends_on = [module.networking]
}

# Create Google Cloud Storage bucket for Materialize persistent data storage
module "storage" {
  source = "../../modules/storage"

  project_id      = var.project_id
  region          = var.region
  prefix          = var.name_prefix
  service_account = module.gke.workload_identity_sa_email
  versioning      = false
  version_ttl     = 7

  labels = var.labels
}

# Install cert-manager for TLS certificates
module "cert_manager" {
  source = "../../../kubernetes/modules/cert-manager"

  enable_service_monitor = module.monitoring_crds.crds_installed

  node_selector = local.generic_node_labels

  depends_on = [
    module.gke,
    module.coredns,
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

# Install Materialize Kubernetes operator for managing Materialize instances
module "operator" {
  source = "../../modules/operator"

  monitoring_namespace = module.monitoring_crds.namespace
  # module.monitoring_crds creates the monitoring namespace.
  create_monitoring_namespace = false

  operator_version = var.materialize_version

  name_prefix = var.name_prefix
  region      = var.region

  # Must match the namespace passed to the gke module: its workload identity
  # binding targets the operator's service account in that namespace.
  operator_namespace = local.materialize_operator_namespace

  # Tolerations and node selector for Materialize instance workloads
  instance_pod_tolerations = local.materialize_tolerations
  instance_node_selector   = local.materialize_node_labels

  # node selector for operator and metrics-server workloads
  operator_node_selector = local.generic_node_labels

  # Must match the node pool, or clusterd pods can't schedule
  swap_enabled = var.materialize_nodepool.swap_enabled

  # Trigger rollouts of Materialize instances when GKE upgrades the node
  # pools they run on, so that their pods move to the replacement nodes
  # gracefully instead of being evicted.
  enable_node_upgrade_rollout_trigger    = var.enable_node_upgrade_rollout_trigger
  node_upgrade_notification_subscription = module.gke.upgrade_notification_subscription
  cluster_name                           = module.gke.cluster_name
  cluster_location                       = module.gke.cluster_location
  node_upgrade_watched_node_pools        = [module.materialize_nodepool.node_pool_name]
  # Workload identity for the operator's Pub/Sub subscription and GKE API reads.
  # The gke module binds it to the chart's "orchestratord" service account.
  operator_service_account_annotations = var.enable_node_upgrade_rollout_trigger ? {
    "iam.gke.io/gcp-service-account" = module.gke.workload_identity_sa_email
  } : {}

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
  enable_network_policies = true
  depends_on = [
    module.gke,
    module.generic_nodepool,
    module.coredns,
    module.cert_manager,
  ]
}

module "monitoring" {
  count  = var.enable_observability ? 1 : 0
  source = "../../modules/monitoring"

  prefix     = var.name_prefix
  project_id = var.project_id
  region     = var.region

  # Loki and Thanos write right away and GCS will not delete a non-empty bucket,
  # so without this `terraform destroy` hangs. Set to false for data you need to keep.
  bucket_force_destroy = true

  namespace = module.monitoring_crds.namespace
  # module.monitoring_crds already creates the namespace and CRDs.
  create_namespace       = false
  enable_monitoring_crds = false

  node_selector = local.generic_node_labels
  storage_class = local.storage_class

  # Optional fan-out to Cloud Monitoring, on top of the bundled Thanos. Off by
  # default because GCM bills per custom metric; the tier is the cost lever.
  enable_google_cloud_metrics         = false
  google_cloud_metrics_min_importance = "recommended"

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
  materialize_operator_namespace = local.materialize_operator_namespace

  # Grafana gets its own Cloud SQL instance, away from Materialize's metadata.
  grafana_database = {
    network_id = module.networking.network_id
  }

  # The monitoring module refuses a public Grafana with an unrestricted allowlist;
  # `grafana_allow_public_access` is the opt-in that lifts it.
  additional_values = var.grafana_allow_public_access ? [
    yamlencode({ connections = { grafana = { allowPublicAccess = true } } })
  ] : []

  # Same internal/allowlist settings as the Materialize load balancers. `host` is
  # optional since the LB answers on an IP; set it so Grafana's `root_url` is right.
  grafana_load_balancer = {
    internal            = var.internal_load_balancer
    ingress_cidr_blocks = var.ingress_cidr_blocks
    host                = var.grafana_host
  }

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
    module.gke,
    module.generic_nodepool,
    module.coredns,
  ]
}

# Deploy Materialize instance with configured backend connections
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
  source                  = "../../../kubernetes/modules/materialize-instance"
  environmentd_version    = var.materialize_version
  instance_name           = local.materialize_instance_name
  instance_namespace      = local.materialize_instance_namespace
  metadata_backend_url    = local.metadata_backend_url
  persist_backend_url     = local.persist_backend_url
  enable_network_policies = true

  force_rollout   = var.force_rollout
  request_rollout = var.request_rollout

  # OIDC login (Ory, or var.direct_oidc when set). mz_system keeps a password
  # login as the admin fallback.
  external_login_password_mz_system = random_password.external_login_password_mz_system.result
  authenticator_kind                = "Oidc"

  # TODO: KSA-based storage access does not work end to end yet (needs an
  # environmentd client fix), so persist uses HMAC keys.
  service_account_annotations = {
    "iam.gke.io/gcp-service-account" = module.gke.workload_identity_sa_email
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
    module.materialize_nodepool,
    module.coredns,
  ]
}

# Configure load balancers for external access to Materialize services
module "load_balancers" {
  source = "../../modules/load_balancers"

  project_id                 = var.project_id
  network_name               = module.networking.network_name
  prefix                     = var.name_prefix
  node_service_account_email = module.gke.service_account_email
  internal                   = var.internal_load_balancer
  ingress_cidr_blocks        = var.ingress_cidr_blocks
  instance_name              = local.materialize_instance_name
  namespace                  = local.materialize_instance_namespace
  resource_id                = module.materialize_instance.instance_resource_id

  # Console on 443 so OIDC redirects to https://<materialize_console_fqdn>/auth/callback
  # need no :8080 suffix and match Hydra's CORS origins.
  materialize_console_port = 443
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

  # When set, Hydra and Kratos share one hostname behind a reverse proxy. The UI
  # and Polis keep their own hostnames.
  single_domain_fqdn = var.ory_single_domain_fqdn

  kratos_dsn = local.ory_kratos_dsn
  hydra_dsn  = local.ory_hydra_dsn

  # Polis (SAML-to-OIDC bridge). Off by default. Its chart and image come through
  # the OEL registry proxy using the license key, so no extra credential is needed.
  enable_polis = var.enable_polis
  polis_fqdn   = var.enable_polis ? var.ory_polis_fqdn : null
  polis_dsn    = var.enable_polis ? local.ory_polis_dsn : null

  polis_helm_values = var.polis_helm_values

  oel_registry    = var.ory_oel_registry
  oel_image_tag   = var.ory_oel_image_tag
  license_key_jwt = var.license_key

  cert_issuer_ref                 = local.cert_issuer
  cert_issuer_signs_cluster_local = var.cert_issuer_ref == null

  # Materialize integration: OAuth2 client CRD and ory-side ingress NetworkPolicy.
  materialize_namespace    = local.materialize_instance_namespace
  materialize_console_fqdn = var.materialize_console_fqdn

  # GKE Internal TCP/UDP Network LB when var.internal_load_balancer = true,
  # external NLB otherwise.
  lb_annotations = var.internal_load_balancer ? {
    "networking.gke.io/load-balancer-type" = "Internal"
  } : {}

  # Firewall the public Ory LBs to ory_lb_source_ranges. Polis gets its own
  # allowlist when ory_polis_source_ranges or okta-scim-source-ranges.json is set,
  # so a default 0.0.0.0/0 ingress_cidr_blocks never reopens a Polis locked to Okta.
  lb_overrides = merge(
    var.internal_load_balancer ? {} : {
      for role in ["hydra", "kratos", "ui", "polis"] : role => { source_ranges = local.ory_lb_source_ranges }
    },
    length(local.polis_lb_source_ranges) > 0 ? {
      polis = { source_ranges = local.polis_lb_source_ranges }
    } : {},
  )

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
  ]
}

# Upgrade path: this NetworkPolicy moved from ory-stack to materialize-instance.
# The old ory-stack console LoadBalancer is destroyed on apply and
# module.load_balancers moves the console to 443; repoint the console DNS record.
moved {
  from = module.ory.kubernetes_network_policy_v1.materialize_to_ory_egress[0]
  to   = module.materialize_instance.kubernetes_network_policy_v1.allow_ory_egress[0]
}
