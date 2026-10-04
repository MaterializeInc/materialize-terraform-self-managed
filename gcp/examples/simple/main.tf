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

# lazy_load defers kubeconfig resolution to first use. Without it, plan fails
# with an empty REST config while module.gke outputs are still unknown. See:
# https://registry.terraform.io/providers/alekc/kubectl/latest/docs#troubleshooting
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

  gke_config = {
    # C4A local SSDs are only available on -lssd machine variants.
    machine_type = "c4a-highmem-8-lssd"
    # C4A/C4 only support Hyperdisk boot disks. Explicit so that pools
    # upgraded from an older machine series don't keep pd-balanced.
    disk_type    = "hyperdisk-balanced"
    disk_size_gb = 100
    min_nodes    = 2
    max_nodes    = 5
  }

  database_config = {
    tier = "db-custom-N4-2-4096"
    # N4 instances only support Hyperdisk Balanced, not PD_SSD.
    disk_type = "HYPERDISK_BALANCED"
    database  = { name = "materialize", charset = "UTF8", collation = "en_US.UTF8" }
    user_name = "materialize"
  }

  # c4a-highmem-8-lssd bundles exactly 2 local SSDs; the count must match.
  local_ssd_count = 2
  swap_enabled    = true

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
  # Not `standard-rwo`: C4/C4A node pools take only Hyperdisk, and every default
  # GKE class is Persistent Disk, so a PVC on those pools would never attach.
  storage_class = kubernetes_storage_class.hyperdisk_balanced.metadata[0].name

}

# GKE ships no Hyperdisk class, so create one. Not the default, so other
# workloads keep `standard-rwo`. Not gated on `enable_observability`: any PVC on
# C4/C4A pools needs it, and other workloads may already be bound to it.
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

  depends_on = [module.networking]

  project_id   = var.project_id
  region       = var.region
  prefix       = var.name_prefix
  network_name = module.networking.network_name
  # Only one subnet here; with several, pick the right one by name.
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

  # STABLE (1.34.x): REGULAR's 1.35.x leaks the k8s-<cluster-uid>-node-http-hc
  # firewall on cluster destroy, leaving the VPC undeletable.
  release_channel = "STABLE"
}

# Install the monitoring namespace and CRDs before anything that ships a
# ServiceMonitor, or those charts fail or silently drop it. Components enable
# their monitors from `crds_installed`, which also orders them after the CRDs.
# The namespace is created even when observability is off.
module "monitoring_crds" {
  source = "../../../kubernetes/modules/monitoring-crds"

  namespace    = "monitoring"
  install_crds = var.enable_observability

  depends_on = [module.gke]
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

# Create and configure generic node pool for all workloads except Materialize
module "generic_nodepool" {
  source     = "../../modules/nodepool"
  depends_on = [module.gke]

  prefix                = "${var.name_prefix}-generic"
  region                = var.region
  enable_private_nodes  = true
  cluster_name          = module.gke.cluster_name
  project_id            = var.project_id
  min_nodes             = 2
  max_nodes             = 5
  machine_type          = "c4-standard-8"
  disk_type             = "hyperdisk-balanced"
  disk_size_gb          = 50
  service_account_email = module.gke.service_account_email
  labels                = local.generic_node_labels
  swap_enabled          = false
  local_ssd_count       = 0
}

# Create and configure Materialize-dedicated node pool with taints
module "materialize_nodepool" {
  source     = "../../modules/nodepool"
  depends_on = [module.gke]

  prefix                = "${var.name_prefix}-mz"
  region                = var.region
  enable_private_nodes  = true
  cluster_name          = module.gke.cluster_name
  project_id            = var.project_id
  min_nodes             = local.gke_config.min_nodes
  max_nodes             = local.gke_config.max_nodes
  machine_type          = local.gke_config.machine_type
  disk_type             = local.gke_config.disk_type
  disk_size_gb          = local.gke_config.disk_size_gb
  service_account_email = module.gke.service_account_email
  labels                = merge(var.labels, local.materialize_node_labels)
  # Materialize-specific taint to isolate workloads
  node_taints = local.materialize_node_taints

  swap_enabled    = local.swap_enabled
  local_ssd_count = local.local_ssd_count
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
  depends_on = [
    module.gke,
    module.generic_nodepool,
  ]
}

resource "random_password" "external_login_password_mz_system" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Set up PostgreSQL database instance for Materialize metadata storage
module "database" {
  source     = "../../modules/database"
  depends_on = [module.networking]

  databases = [local.database_config.database]
  # We don't provide password, so random password is generated
  users = [{ name = local.database_config.user_name }]

  project_id = var.project_id
  region     = var.region
  prefix     = var.name_prefix
  network_id = module.networking.network_id

  # Random name suffix, so a half-created instance from a failed apply with lost
  # state does not block the next apply with a 409 "instance already exists".
  random_instance_name = true

  tier      = local.database_config.tier
  disk_type = local.database_config.disk_type

  labels = var.labels
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

# Install cert-manager for SSL certificate management and create cluster issuer
module "cert_manager" {
  source = "../../../kubernetes/modules/cert-manager"

  enable_service_monitor = module.monitoring_crds.crds_installed

  node_selector = local.generic_node_labels

  depends_on = [
    module.gke,
    module.generic_nodepool,
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

  # Tolerations and node selector for Materialize instance pods
  instance_pod_tolerations = local.materialize_tolerations
  instance_node_selector   = local.materialize_node_labels

  # node selector for operator and metrics-server workloads
  operator_node_selector = local.generic_node_labels

  # Roll out Materialize instances when GKE upgrades their node pools, so pods
  # move to the new nodes gracefully instead of being evicted.
  enable_node_upgrade_rollout_trigger    = var.enable_node_upgrade_rollout_trigger
  node_upgrade_notification_subscription = module.gke.upgrade_notification_subscription
  cluster_name                           = module.gke.cluster_name
  cluster_location                       = module.gke.cluster_location
  node_upgrade_watched_node_pools        = [module.materialize_nodepool.node_pool_name]
  # Workload identity for the operator's Pub/Sub and GKE API access. The gke
  # module binds the chart's service account ("orchestratord") in its namespace.
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
    module.database,
    module.storage,
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

  # Loki and Thanos write immediately and a non-empty bucket cannot be deleted,
  # so without this `terraform destroy` gets stuck. Set to false for real data.
  bucket_force_destroy = true

  namespace = module.monitoring_crds.namespace
  # module.monitoring_crds already creates the namespace and installs the CRDs.
  create_namespace       = false
  enable_monitoring_crds = false

  node_selector = local.generic_node_labels
  storage_class = local.storage_class

  # Optional fan-out to Cloud Monitoring, on top of the bundled Thanos. Off by
  # default because GCM bills per custom metric; the tier is the cost lever.
  enable_google_cloud_metrics         = false
  google_cloud_metrics_min_importance = "recommended"

  # Cloud Monitoring metrics for the metadata database and persist bucket, named
  # here so nothing else in the project is pulled (the module adds its own
  # buckets and Grafana's database). Compute Engine quota usage covers every VM
  # in the region, since that is what stops a node pool from growing.
  provider_metrics = var.enable_provider_metrics ? {
    cloud_sql_instances = [module.database.instance_name]
    gcs_buckets         = [module.storage.bucket_name]
    compute_regions     = [var.region]
  } : null

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

  materialize_instance_namespace = local.materialize_instance_namespace
  materialize_operator_namespace = local.materialize_operator_namespace

  # Dedicated Cloud SQL instance so Grafana dashboards and API tokens survive a
  # pod restart.
  grafana_database = {
    network_id = module.networking.network_id
  }

  # The monitoring module refuses a public Grafana with an unrestricted allowlist;
  # this opt-in lifts that. See `grafana_allow_public_access`.
  additional_values = var.grafana_allow_public_access ? [
    yamlencode({ connections = { grafana = { allowPublicAccess = true } } })
  ] : []

  # Same internal/allowlist variables as the Materialize load balancers. The load
  # balancer answers on an IP; set `host` so Grafana's `root_url` is correct.
  grafana_load_balancer = {
    internal            = var.internal_load_balancer
    ingress_cidr_blocks = var.ingress_cidr_blocks
    host                = var.grafana_host
  }

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
    module.gke,
    module.generic_nodepool,
    module.coredns,
  ]
}

# Deploy Materialize instance with configured backend connections
module "materialize_instance" {
  source                  = "../../../kubernetes/modules/materialize-instance"
  environmentd_version    = var.materialize_version
  instance_name           = local.materialize_instance_name
  instance_namespace      = local.materialize_instance_namespace
  metadata_backend_url    = local.metadata_backend_url
  persist_backend_url     = local.persist_backend_url
  enable_network_policies = true

  # Rollout configuration
  force_rollout   = var.force_rollout
  request_rollout = var.request_rollout

  # The password for the external login to the Materialize instance
  external_login_password_mz_system = random_password.external_login_password_mz_system.result
  authenticator_kind                = "Password"

  # GCP workload identity annotation for service account
  # TODO: this needs a fix in Environmentd Client. KSA based access to storage doesn't work end to end
  service_account_annotations = {
    "iam.gke.io/gcp-service-account" = module.gke.workload_identity_sa_email
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
    module.gke,
    module.database,
    module.storage,
    module.networking,
    module.self_signed_cluster_issuer,
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

  depends_on = [
    module.materialize_instance,
  ]
}
