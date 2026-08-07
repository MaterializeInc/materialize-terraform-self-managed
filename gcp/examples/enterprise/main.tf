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
  # Not `standard-rwo`: the node pools default to C4/C4A, which take only
  # Hyperdisk — same constraint as their boot disks. Every default GKE class is
  # Persistent Disk, so a PVC on those pools never attaches.
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

# GKE ships no Hyperdisk class, so create one. Not marked default — taking that
# from `standard-rwo` would change provisioning for every other workload.
#
# Deliberately not gated on `enable_observability`, even though monitoring is
# the only module that reads it today. On C4/C4A node pools any workload
# needing a PVC hits the same Persistent Disk wall, so the class is generally
# useful; tying it to the observability flag would mean turning monitoring off
# silently removes a class other workloads may already be bound to.
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
  # we only have one subnet, so we can use the first one
  # if multiple subnets are created, we need to use the specific subnet name here
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
  depends_on                                  = [module.generic_nodepool]
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
  # We don't provide password, so random password is generated
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

# Separate Cloud SQL instance for Ory (Kratos + Hydra)
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

# Install cert-manager for SSL certificate management and create cluster issuer
module "cert_manager" {
  source = "../../../kubernetes/modules/cert-manager"

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

  operator_version = var.materialize_version

  name_prefix = var.name_prefix
  region      = var.region

  # Must match the namespace passed to the gke module: its workload identity
  # binding targets the operator's service account in that namespace.
  operator_namespace = local.materialize_operator_namespace

  # ARM tolerations and node selector for all operator workloads on GCP
  instance_pod_tolerations = local.materialize_tolerations
  instance_node_selector   = local.materialize_node_labels

  # node selector for operator and metrics-server workloads
  operator_node_selector = local.generic_node_labels

  # Trigger rollouts of Materialize instances when GKE upgrades the node
  # pools they run on, so that their pods move to the replacement nodes
  # gracefully instead of being evicted.
  enable_node_upgrade_rollout_trigger    = var.enable_node_upgrade_rollout_trigger
  node_upgrade_notification_subscription = module.gke.upgrade_notification_subscription
  cluster_name                           = module.gke.cluster_name
  cluster_location                       = module.gke.cluster_location
  node_upgrade_watched_node_pools        = [module.materialize_nodepool.node_pool_name]
  # Grant the operator workload identity access for its Pub/Sub subscription
  # and GKE API reads. The gke module's workload identity binding targets the
  # chart's service account (its orchestratord_service_account_name variable,
  # default "orchestratord") in the operator namespace.
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

  # Matches what these examples already pass to `module.storage`. Loki and
  # Thanos start writing immediately, and neither S3 nor GCS will delete a
  # non-empty bucket, so without this `terraform destroy` wedges on the
  # telemetry buckets. Set to false for anything you cannot afford to lose.
  bucket_force_destroy = true

  namespace = "monitoring"
  # The operator module creates the "monitoring" namespace.
  create_namespace = false

  node_selector = local.generic_node_labels
  storage_class = local.storage_class

  # Optional fan-out to Cloud Monitoring, on top of the bundled Thanos. Off by
  # default because GCM bills per custom metric; the tier is the cost lever.
  enable_google_cloud_metrics         = false
  google_cloud_metrics_min_importance = "recommended"

  materialize_instance_namespace = local.materialize_instance_namespace
  materialize_operator_namespace = local.materialize_operator_namespace

  # A dedicated Cloud SQL instance for Grafana's own state, separate from
  # `module.database` so Grafana's blast radius stays away from Materialize's
  # metadata.
  grafana_database = var.enable_grafana_database ? {
    network_id = module.networking.network_id
  } : null

  # Internal by default; going public requires `ingress_cidr_blocks`, which the
  # module enforces rather than merely defaulting. On an internal load balancer
  # the allowlist is the VPC's own subnet ranges.
  grafana_load_balancer = var.grafana_host == null ? null : {
    host                = var.grafana_host
    internal            = var.internal_load_balancer
    ingress_cidr_blocks = var.internal_load_balancer ? module.networking.subnets_ips : var.ingress_cidr_blocks
  }

  depends_on = [
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

  # Use OIDC authentication via Ory Hydra. The external_login_password is still required
  # as a fallback for the mz_system admin user.
  external_login_password_mz_system = random_password.external_login_password_mz_system.result
  authenticator_kind                = "Oidc"

  # GCP workload identity annotation for service account
  # TODO: this needs a fix in Environmentd Client. KSA based access to storage doesn't work end to end
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

  # OIDC config; client_id is the Hydra Maester-generated UUID read from
  # the OAuth2 client Secret. system_parameters can also set any of the
  # parameters listed at https://materialize.com/docs/sql/alter-system-set/#key-configuration-parameters
  system_parameters = {
    oidc_issuer               = module.ory.hydra_external_url
    oidc_audience             = jsonencode([module.ory.oauth2_client_id])
    oidc_authentication_claim = "email"
    console_oidc_client_id    = module.ory.oauth2_client_id
    console_oidc_scopes       = "openid email"
  }

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

  # Serve the console on 443 (the canonical HTTPS port) so browser OIDC
  # redirects to https://<materialize_console_fqdn>/auth/callback resolve without
  # a :8080 suffix, and CORS origins match Hydra's cors_allowed_origins.
  materialize_console_port = 443
}

# Ory stack (Kratos + Hydra + selfservice UI + Materialize bridge).
# Example feeds cloud-specific inputs (DSNs, LB annotations, cert issuer)
# and reads back the OIDC issuer URL + OAuth2 client id from its outputs.
module "ory" {
  source = "../../../kubernetes/modules/ory-stack"

  namespace = local.ory_namespace

  hydra_fqdn  = var.ory_hydra_fqdn
  kratos_fqdn = var.ory_kratos_fqdn
  ui_fqdn     = var.ory_ui_fqdn

  kratos_dsn = local.ory_kratos_dsn
  hydra_dsn  = local.ory_hydra_dsn

  # Polis (SAML-to-OIDC bridge). Off by default.
  enable_polis = var.enable_polis
  polis_fqdn   = var.enable_polis ? var.ory_polis_fqdn : null
  polis_dsn    = var.enable_polis ? local.ory_polis_dsn : null

  polis_helm_values = var.polis_helm_values

  oel_registry    = var.ory_oel_registry
  oel_image_tag   = var.ory_oel_image_tag
  license_key_jwt = var.license_key

  cert_issuer_ref                 = local.cert_issuer
  cert_issuer_signs_cluster_local = var.cert_issuer_ref == null

  # Materialize integration: OAuth2 client CRD + ory-side ingress NetworkPolicy.
  materialize_namespace    = local.materialize_instance_namespace
  materialize_console_fqdn = var.materialize_console_fqdn

  # GKE Internal TCP/UDP Network LB when var.internal_load_balancer = true,
  # external NLB otherwise.
  lb_annotations = var.internal_load_balancer ? {
    "networking.gke.io/load-balancer-type" = "Internal"
  } : {}

  node_selector = local.generic_node_labels

  upstream_oidc_providers = var.upstream_oidc_providers

  depends_on = [
    module.coredns,
  ]
}

# State migration: the ory -> materialize egress NetworkPolicy moved from
# ory-stack to materialize-instance. The console HTTPS LoadBalancer that used
# to live in ory-stack is destroyed on apply; the existing per-cloud console
# LB (module.load_balancers) is retargeted from 8080 to 443 in place. Update
# the console DNS record after apply to point at the retargeted LB IP.
moved {
  from = module.ory.kubernetes_network_policy_v1.materialize_to_ory_egress[0]
  to   = module.materialize_instance.kubernetes_network_policy_v1.allow_ory_egress[0]
}
