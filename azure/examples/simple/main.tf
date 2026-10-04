provider "azurerm" {
  # Set the Azure subscription ID here or use the AZURE_SUBSCRIPTION_ID environment variable
  subscription_id = var.subscription_id

  # The monitoring storage account disables shared keys, so use Azure AD for
  # storage data-plane calls. The Terraform identity needs a data-plane role
  # (Storage Blob Data Contributor) on it, not just Owner.
  storage_use_azuread = true

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = false
    }
  }
}

provider "kubernetes" {
  host                   = module.aks.cluster_endpoint
  client_certificate     = base64decode(module.aks.kube_config[0].client_certificate)
  client_key             = base64decode(module.aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(module.aks.kube_config[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = module.aks.cluster_endpoint
    client_certificate     = base64decode(module.aks.kube_config[0].client_certificate)
    client_key             = base64decode(module.aks.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(module.aks.kube_config[0].cluster_ca_certificate)
  }
}

# lazy_load defers kubeconfig resolution to first use. Without it, plan fails
# with an empty REST config while module.aks outputs are still unknown. See:
# https://registry.terraform.io/providers/alekc/kubectl/latest/docs#troubleshooting
provider "kubectl" {
  host                   = module.aks.cluster_endpoint
  client_certificate     = base64decode(module.aks.kube_config[0].client_certificate)
  client_key             = base64decode(module.aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(module.aks.kube_config[0].cluster_ca_certificate)

  load_config_file = false
  lazy_load        = true
}


locals {
  vnet_config = {
    address_space                      = "10.0.0.0/16"
    aks_subnet_cidr                    = "10.0.0.0/20"
    postgres_subnet_cidr               = "10.0.16.0/24"
    enable_api_server_vnet_integration = true
    api_server_subnet_cidr             = "10.0.32.0/27" # 32 IPs reserved for the delegated API server subnet
  }

  aks_config = {
    kubernetes_version         = "1.34"
    service_cidr               = "10.1.0.0/16"
    enable_azure_monitor       = false
    log_analytics_workspace_id = null
  }

  node_pool_config = {
    vm_size              = "Standard_E4pds_v6"
    auto_scaling_enabled = true
    min_nodes            = 2
    max_nodes            = 5
    node_count           = null
    disk_size_gb         = 100
    swap_enabled         = true
  }

  database_config = {
    sku_name                      = "GP_Standard_D2ds_v5"
    postgres_version              = "18"
    storage_mb                    = 32768
    backup_retention_days         = 7
    administrator_login           = "materialize"
    administrator_password        = null # Will generate random password
    database_name                 = "materialize"
    public_network_access_enabled = false
  }

  storage_container_name = "materialize"

  database_statement_timeout = "15min"

  metadata_backend_url = format(
    "postgres://%s:%s@%s/%s?sslmode=require&options=-c%%20statement_timeout%%3D%s",
    module.database.administrator_login,
    urlencode(module.database.administrator_password),
    module.database.server_fqdn,
    local.database_config.database_name,
    local.database_statement_timeout
  )

  persist_backend_url = format(
    "%s%s",
    module.storage.primary_blob_endpoint,
    module.storage.container_name,
  )

  materialize_instance_namespace = "materialize-environment"
  # Set here and passed to the operator, monitoring-crds and monitoring modules
  # so they cannot drift apart; monitoring scopes its scrape targets to them.
  materialize_operator_namespace = "materialize"
  monitoring_namespace           = "monitoring"
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

  # https://learn.microsoft.com/en-us/azure/aks/concepts-storage#storage-classes
  storage_class = "managed-csi"

}


resource "azurerm_resource_group" "materialize" {
  name     = var.resource_group_name
  location = var.location
}


module "networking" {
  source = "../../modules/networking"

  resource_group_name                = azurerm_resource_group.materialize.name
  location                           = var.location
  prefix                             = var.name_prefix
  vnet_address_space                 = local.vnet_config.address_space
  aks_subnet_cidr                    = local.vnet_config.aks_subnet_cidr
  postgres_subnet_cidr               = local.vnet_config.postgres_subnet_cidr
  enable_api_server_vnet_integration = local.vnet_config.enable_api_server_vnet_integration
  api_server_subnet_cidr             = local.vnet_config.api_server_subnet_cidr

  tags = var.tags

  depends_on = [azurerm_resource_group.materialize]
}

# AKS Cluster with Default Node Pool
module "aks" {
  source = "../../modules/aks"

  resource_group_name = azurerm_resource_group.materialize.name
  kubernetes_version  = local.aks_config.kubernetes_version
  service_cidr        = local.aks_config.service_cidr
  location            = var.location
  prefix              = var.name_prefix
  vnet_name           = module.networking.vnet_name
  subnet_name         = module.networking.aks_subnet_name
  subnet_id           = module.networking.aks_subnet_id

  enable_api_server_vnet_integration = local.vnet_config.enable_api_server_vnet_integration
  k8s_apiserver_authorized_networks  = concat(var.k8s_apiserver_authorized_networks, ["${module.networking.nat_gateway_public_ip}/32"])
  api_server_subnet_id               = module.networking.api_server_subnet_id

  # Default node pool with autoscaling (runs all workloads except Materialize)
  default_node_pool_vm_size             = "Standard_D4ps_v6"
  default_node_pool_enable_auto_scaling = true
  default_node_pool_min_count           = 2
  default_node_pool_max_count           = 5
  default_node_pool_node_labels         = local.generic_node_labels

  # Optional: Enable monitoring
  enable_azure_monitor       = local.aks_config.enable_azure_monitor
  log_analytics_workspace_id = local.aks_config.log_analytics_workspace_id

  tags = var.tags

  depends_on = [azurerm_resource_group.materialize]
}

# Install the monitoring namespace and CRDs before anything that ships a
# ServiceMonitor, or those charts fail or silently drop it. Components enable
# their monitors from `crds_installed`, which also orders them after the CRDs.
# The namespace is created even when observability is off.
module "monitoring_crds" {
  source = "../../../kubernetes/modules/monitoring-crds"

  namespace    = local.monitoring_namespace
  install_crds = var.enable_observability

  depends_on = [module.aks]
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

# Materialize-dedicated node pool with taints
module "materialize_nodepool" {
  source = "../../modules/nodepool"

  prefix     = var.name_prefix
  cluster_id = module.aks.cluster_id
  subnet_id  = module.networking.aks_subnet_id

  # Workload-specific configuration
  autoscaling_config = {
    enabled    = local.node_pool_config.auto_scaling_enabled
    min_nodes  = local.node_pool_config.min_nodes
    max_nodes  = local.node_pool_config.max_nodes
    node_count = local.node_pool_config.node_count
  }

  vm_size      = local.node_pool_config.vm_size
  disk_size_gb = local.node_pool_config.disk_size_gb
  swap_enabled = local.node_pool_config.swap_enabled

  labels = local.materialize_node_labels

  # Taint to isolate Materialize workloads. AKS webhooks block removing it once
  # applied: https://github.com/Azure/AKS/issues/2934
  node_taints = local.materialize_node_taints

  tags = var.tags

  depends_on = [azurerm_resource_group.materialize]
}


module "database" {
  source = "../../modules/database"

  depends_on = [module.networking]

  databases = [
    {
      name      = local.database_config.database_name
      charset   = "UTF8"
      collation = "en_US.utf8"
    }
  ]

  # Administrator configuration
  administrator_login = local.database_config.administrator_login

  # Infrastructure configuration
  resource_group_name = azurerm_resource_group.materialize.name
  location            = var.location
  prefix              = var.name_prefix
  subnet_id           = module.networking.postgres_subnet_id
  private_dns_zone_id = module.networking.private_dns_zone_id

  # Database server configuration
  sku_name                      = local.database_config.sku_name
  postgres_version              = local.database_config.postgres_version
  storage_mb                    = local.database_config.storage_mb
  backup_retention_days         = local.database_config.backup_retention_days
  public_network_access_enabled = local.database_config.public_network_access_enabled

  tags = var.tags
}

module "storage" {
  source = "../../modules/storage"

  resource_group_name            = azurerm_resource_group.materialize.name
  location                       = var.location
  prefix                         = var.name_prefix
  workload_identity_principal_id = module.aks.workload_identity_principal_id
  subnets                        = [module.networking.aks_subnet_id]
  container_name                 = local.storage_container_name
  versioning                     = false

  # Workload identity federation configuration
  workload_identity_id      = module.aks.workload_identity_id
  oidc_issuer_url           = module.aks.cluster_oidc_issuer_url
  service_account_namespace = local.materialize_instance_namespace
  service_account_name      = local.materialize_instance_name

  storage_account_tags = var.tags

  depends_on = [azurerm_resource_group.materialize]
}

resource "random_password" "external_login_password_mz_system" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Deploy custom CoreDNS with TTL 0 (AKS's coredns doesn't support disabling caching)
module "coredns" {
  source             = "../../../kubernetes/modules/coredns"
  node_selector      = local.generic_node_labels
  kubeconfig_data    = module.aks.kube_config_raw
  cluster_identifier = module.aks.cluster_name
  depends_on = [
    module.aks,
    module.networking,
  ]
}

module "cert_manager" {
  source = "../../../kubernetes/modules/cert-manager"

  enable_service_monitor = module.monitoring_crds.crds_installed

  node_selector = local.generic_node_labels

  depends_on = [
    module.aks,
    module.networking,
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

module "operator" {
  source = "../../modules/operator"

  # module.monitoring_crds creates the monitoring namespace.
  create_monitoring_namespace = false

  operator_version = var.materialize_version

  name_prefix = var.name_prefix
  location    = var.location

  # Tolerations and node selector for Materialize instance pods
  instance_pod_tolerations = local.materialize_tolerations
  instance_node_selector   = local.materialize_node_labels

  # node selector for operator and metrics-server workloads
  operator_node_selector = local.generic_node_labels

  operator_namespace   = local.materialize_operator_namespace
  monitoring_namespace = module.monitoring_crds.namespace

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
    module.aks,
    module.database,
    module.storage,
    module.coredns,
    module.cert_manager,
  ]
}

module "monitoring" {
  count  = var.enable_observability ? 1 : 0
  source = "../../modules/monitoring"

  prefix              = var.name_prefix
  resource_group_name = azurerm_resource_group.materialize.name
  location            = var.location

  namespace = module.monitoring_crds.namespace
  # module.monitoring_crds already creates the namespace and installs the CRDs.
  create_namespace       = false
  enable_monitoring_crds = false

  oidc_issuer_url = module.aks.cluster_oidc_issuer_url

  node_selector = local.generic_node_labels
  storage_class = local.storage_class

  # No zones are set on the node pools, so the chart's hard two-zone spread on
  # Thanos Receive and Loki ingesters would leave them Pending forever. Raise
  # this to the real zone count if you give the node pools zones.
  min_zones = 1

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

  # Azure Monitor metrics for the metadata database and persist storage account
  # (the module adds its own storage account and Grafana's database). Node VMs
  # are found in the cluster's node resource group. The gateway's identity can
  # read only these, so nothing else in the subscription is pulled.
  provider_metrics = var.enable_provider_metrics ? {
    postgres_server_ids = [module.database.server_id]
    storage_account_ids = [module.storage.storage_account_id]
    aks_clusters = [{
      id                  = module.aks.cluster_id
      node_resource_group = module.aks.cluster_node_resource_group
    }]
  } : null

  # Dedicated Flexible Server so Grafana dashboards and API tokens survive a pod
  # restart. Separate from `module.database` because a Flexible Server has one
  # admin login and no ARM resource for additional roles.
  grafana_database = {
    subnet_id           = module.networking.postgres_subnet_id
    private_dns_zone_id = module.networking.private_dns_zone_id
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
    module.aks,
    module.coredns,
  ]
}

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
  authenticator_kind                = "Password"
  external_login_password_mz_system = random_password.external_login_password_mz_system.result

  # Azure workload identity annotations for service account
  service_account_annotations = {
    "azure.workload.identity/client-id" = module.aks.workload_identity_client_id
  }
  pod_labels = {
    "azure.workload.identity/use" = "true"
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
    module.aks,
    module.database,
    module.storage,
    module.networking,
    module.self_signed_cluster_issuer,
    module.operator,
    module.materialize_nodepool,
    module.coredns,
  ]
}

module "load_balancers" {
  source = "../../modules/load_balancers"

  instance_name       = local.materialize_instance_name
  namespace           = local.materialize_instance_namespace
  resource_id         = module.materialize_instance.instance_resource_id
  internal            = var.internal_load_balancer
  ingress_cidr_blocks = var.internal_load_balancer ? null : var.ingress_cidr_blocks

  depends_on = [
    module.materialize_instance,
  ]
}
