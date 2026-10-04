# =============================================================================
# Migration Reference Configuration
# =============================================================================
# Migrates from the old monolithic Azure module (azure-old/) to azure/modules/*
# and kubernetes/modules/*. For zero downtime these stay INLINE:
# 1. AKS: the new module's NAT gateway outbound_type and cilium network policy
#    both force cluster recreation.
# 2. Networking: the new module uses the AVM VNet module and a NAT gateway.
# 3. Database: the old server name is {prefix}-{random}-pg, the new module's is
#    {prefix}-pg.
# After migration you can move these to the new modules one at a time.
# =============================================================================

# -----------------------------------------------------------------------------
# Providers
# -----------------------------------------------------------------------------

provider "azurerm" {
  subscription_id = var.subscription_id

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
  host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
  }
}

# lazy_load (alekc/kubectl v2.4.0+) defers kubeconfig resolution until first use.
# Without it, plans fail with an empty REST config while cluster outputs are unknown.
# See https://registry.terraform.io/providers/alekc/kubectl/latest/docs#troubleshooting
provider "kubectl" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)

  load_config_file = false
  lazy_load        = true
}

# -----------------------------------------------------------------------------
# Resource Group (existing, read as a data source)
# -----------------------------------------------------------------------------

data "azurerm_resource_group" "materialize" {
  name = var.resource_group_name
}

# -----------------------------------------------------------------------------
# Networking (INLINE, preserves the old module resources)
# -----------------------------------------------------------------------------
# State paths after migration:
#   azurerm_virtual_network.vnet
#   azurerm_subnet.aks
#   azurerm_subnet.postgres
#   random_id.dns_zone_suffix
#   azurerm_private_dns_zone.postgres
#   azurerm_private_dns_zone_virtual_network_link.postgres

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.name_prefix}-vnet"
  resource_group_name = data.azurerm_resource_group.materialize.name
  location            = var.location
  address_space       = [var.vnet_address_space]
  tags                = local.common_labels
}

resource "azurerm_subnet" "aks" {
  name                 = "${var.name_prefix}-aks-subnet"
  resource_group_name  = data.azurerm_resource_group.materialize.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.aks_subnet_cidr]

  service_endpoints = ["Microsoft.Storage", "Microsoft.Sql"]
}

resource "azurerm_subnet" "postgres" {
  name                 = "${var.name_prefix}-pg-subnet"
  resource_group_name  = data.azurerm_resource_group.materialize.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.postgres_subnet_cidr]

  service_endpoints = ["Microsoft.Storage"]

  delegation {
    name = "postgres-delegation"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "random_id" "dns_zone_suffix" {
  byte_length = 4
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "materialize${random_id.dns_zone_suffix.hex}.postgres.database.azure.com"
  resource_group_name = data.azurerm_resource_group.materialize.name
  tags                = local.common_labels
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${var.name_prefix}-pg-dns-link"
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  resource_group_name   = data.azurerm_resource_group.materialize.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = true
  tags                  = local.common_labels
}

# -----------------------------------------------------------------------------
# AKS Cluster (INLINE, preserves the old cluster config)
# -----------------------------------------------------------------------------
# State paths after migration:
#   azurerm_user_assigned_identity.aks_identity
#   azurerm_role_assignment.aks_network_contributer
#   azurerm_user_assigned_identity.workload_identity
#   azurerm_kubernetes_cluster.aks
#   azurerm_kubernetes_cluster_node_pool.system
#
# MIGRATION: the old AKS module used network_plugin and network_policy "azure",
# no outbound_type (loadBalancer) and a separate "materialize" node pool for
# system workloads. Kept as is to avoid cluster recreation.

resource "azurerm_user_assigned_identity" "aks_identity" {
  name                = "${var.name_prefix}-aks-identity"
  resource_group_name = data.azurerm_resource_group.materialize.name
  location            = var.location
  tags                = local.common_labels
}

data "azurerm_subscription" "current" {}

resource "azurerm_role_assignment" "aks_network_contributer" {
  scope                = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${data.azurerm_resource_group.materialize.name}/providers/Microsoft.Network/virtualNetworks/${azurerm_virtual_network.vnet.name}/subnets/${azurerm_subnet.aks.name}"
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_identity.principal_id
}

resource "azurerm_user_assigned_identity" "workload_identity" {
  name                = "${var.name_prefix}-workload-identity"
  resource_group_name = data.azurerm_resource_group.materialize.name
  location            = var.location
  tags                = local.common_labels
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.name_prefix}-aks"
  resource_group_name = data.azurerm_resource_group.materialize.name
  location            = var.location
  dns_prefix          = "${var.name_prefix}-aks"
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    temporary_name_for_rotation = "default2"
    name                        = "default"
    vm_size                     = var.default_node_pool_vm_size
    node_count                  = 1
    vnet_subnet_id              = azurerm_subnet.aks.id

    upgrade_settings {
      max_surge                     = "10%"
      drain_timeout_in_minutes      = 0
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks_identity.id]
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # MIGRATION: changing network_plugin or network_policy, or adding
  # outbound_type, recreates the cluster.
  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
    service_cidr   = var.service_cidr
    dns_service_ip = cidrhost(var.service_cidr, 10)
  }

  tags = local.common_labels

  depends_on = [
    azurerm_role_assignment.aks_network_contributer,
  ]
}

# MIGRATION: the old AKS module's "materialize" node pool, which runs system
# pods. Kept (as "system" in state) so those nodes are not lost.
resource "azurerm_kubernetes_cluster_node_pool" "system" {
  name                        = substr(replace(var.name_prefix, "-", ""), 0, 12)
  temporary_name_for_rotation = "${substr(replace(var.name_prefix, "-", ""), 0, 12)}2"
  kubernetes_cluster_id       = azurerm_kubernetes_cluster.aks.id
  vm_size                     = var.system_node_pool_vm_size
  auto_scaling_enabled        = true
  min_count                   = var.system_node_pool_min_nodes
  max_count                   = var.system_node_pool_max_nodes
  vnet_subnet_id              = azurerm_subnet.aks.id
  os_disk_size_gb             = var.system_node_pool_disk_size_gb

  node_labels = {
    "workload" = "system"
  }

  upgrade_settings {
    max_surge                     = "10%"
    drain_timeout_in_minutes      = 0
    node_soak_duration_in_minutes = 0
  }

  tags = local.common_labels
}

# -----------------------------------------------------------------------------
# Materialize Node Pool
# -----------------------------------------------------------------------------
# State path: module.materialize_nodepool.*

module "materialize_nodepool" {
  source = "../../modules/nodepool"

  prefix     = "${var.name_prefix}-mz-swap"
  cluster_id = azurerm_kubernetes_cluster.aks.id
  subnet_id  = azurerm_subnet.aks.id

  autoscaling_config = {
    enabled    = true
    min_nodes  = var.materialize_node_pool_min_nodes
    max_nodes  = var.materialize_node_pool_max_nodes
    node_count = null
  }

  vm_size      = var.materialize_node_pool_vm_size
  disk_size_gb = var.materialize_node_pool_disk_size_gb
  swap_enabled = true

  # MIGRATION: the old module used v0.4.0; the module default is v0.4.1.
  disk_setup_image = var.disk_setup_image

  labels = local.common_labels
  tags   = local.common_labels

  depends_on = [azurerm_kubernetes_cluster.aks]
}

# -----------------------------------------------------------------------------
# Database (INLINE, preserves the old {prefix}-{random}-pg naming)
# -----------------------------------------------------------------------------
# State paths after migration:
#   random_string.postgres_name_suffix
#   azurerm_postgresql_flexible_server.postgres
#   azurerm_postgresql_flexible_server_database.materialize

resource "random_string" "postgres_name_suffix" {
  length  = 4
  special = false
  upper   = false
}

resource "azurerm_postgresql_flexible_server" "postgres" {
  name                = "${var.name_prefix}-${random_string.postgres_name_suffix.result}-pg"
  resource_group_name = data.azurerm_resource_group.materialize.name
  location            = var.location
  version             = var.postgres_version
  delegated_subnet_id = azurerm_subnet.postgres.id
  private_dns_zone_id = azurerm_private_dns_zone.postgres.id

  public_network_access_enabled = false

  administrator_login    = var.database_username
  administrator_password = var.old_db_password

  storage_mb = var.database_storage_mb
  sku_name   = var.database_sku_name

  backup_retention_days = 7

  lifecycle {
    ignore_changes = [
      zone
    ]
  }

  tags = local.common_labels

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.postgres,
  ]
}

resource "azurerm_postgresql_flexible_server_database" "materialize" {
  name      = var.database_name
  server_id = azurerm_postgresql_flexible_server.postgres.id
}

# -----------------------------------------------------------------------------
# Storage
# -----------------------------------------------------------------------------
# State path: module.storage.*
#
# MIGRATION: the old module's resources plus a new federated identity
# credential for workload identity. The old Key Vault and SAS tokens are dropped.

module "storage" {
  source = "../../modules/storage"

  resource_group_name            = data.azurerm_resource_group.materialize.name
  location                       = var.location
  prefix                         = var.name_prefix
  workload_identity_principal_id = azurerm_user_assigned_identity.workload_identity.principal_id
  subnets                        = [azurerm_subnet.aks.id]
  container_name                 = "materialize"
  versioning                     = false

  # Workload identity federation configuration
  workload_identity_id      = azurerm_user_assigned_identity.workload_identity.id
  oidc_issuer_url           = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  service_account_namespace = local.materialize_instance_namespace
  service_account_name      = local.materialize_instance_name

  # MIGRATION: the old module used "Allow"; the module default is the more
  # secure "Deny". You can switch after migration.
  network_rules_default_action = "Allow"

  storage_account_tags = local.common_labels

  depends_on = [azurerm_kubernetes_cluster.aks]
}

# -----------------------------------------------------------------------------
# Certificate Manager
# -----------------------------------------------------------------------------
# State path: module.cert_manager.*
#
# MIGRATION: was module.certificates. The namespace and helm release are moved;
# the self-signed issuer resources are skipped (now kubectl_manifest).

module "cert_manager" {
  source = "../../../kubernetes/modules/cert-manager"

  # MIGRATION: Match old module's chart version to avoid unintended upgrades.
  chart_version = var.cert_manager_chart_version

  # MIGRATION: empty, as in the old module.
  node_selector = {}

  depends_on = [
    azurerm_kubernetes_cluster.aks,
  ]
}

module "self_signed_cluster_issuer" {
  count = var.use_self_signed_cluster_issuer ? 1 : 0

  source = "../../../kubernetes/modules/self-signed-cluster-issuer"

  name_prefix = var.name_prefix

  depends_on = [
    module.cert_manager,
  ]
}

# -----------------------------------------------------------------------------
# Materialize Operator
# -----------------------------------------------------------------------------
# State path: module.operator.*
#
# MIGRATION: the old external module used count; auto-migrate.py drops the [0] index.

module "operator" {
  source = "../../modules/operator"

  # MIGRATION: name_prefix is the helm release name. Keep the old one
  # ("${namespace}-${environment}", by default "materialize-${prefix}") to avoid replacing it.
  # A replacement is usually harmless: the operator is a controller and instances keep running.
  name_prefix      = "materialize-${var.name_prefix}"
  operator_version = var.operator_version
  location         = var.location

  # MIGRATION: the old module set no operator node selectors or tolerations.
  instance_pod_tolerations = []
  instance_node_selector   = {}
  operator_node_selector   = {}

  # AKS has built-in metrics server
  install_metrics_server = false

  # MIGRATION: the old module set TLS via defaultCertificateSpecs and a swap node
  # nodeSelector for environmentd only. instance_node_selector would apply to all
  # workloads (clusterd, balancerd, console too), so use helm_values instead.
  helm_values = merge(
    {
      environmentd = {
        nodeSelector = {
          "materialize.cloud/swap" = "true"
        }
      }
    },
    var.use_self_signed_cluster_issuer ? {
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
  )

  depends_on = [
    azurerm_kubernetes_cluster.aks,
    azurerm_postgresql_flexible_server.postgres,
    module.storage,
  ]
}

# -----------------------------------------------------------------------------
# Materialize Instance
# -----------------------------------------------------------------------------
# State path: module.materialize_instance.*
#
# MIGRATION: namespace and backend secret move here from the old operator
# module. The instance manifest changed to kubectl_manifest, which adopts the
# existing Materialize resource without disruption.

module "materialize_instance" {
  source             = "../../../kubernetes/modules/materialize-instance"
  instance_name      = local.materialize_instance_name
  instance_namespace = local.materialize_instance_namespace

  metadata_backend_url = local.metadata_backend_url
  persist_backend_url  = local.persist_backend_url

  authenticator_kind                = "Password"
  external_login_password_mz_system = var.external_login_password_mz_system

  service_account_annotations = {
    "azure.workload.identity/client-id" = azurerm_user_assigned_identity.workload_identity.client_id
  }
  pod_labels = {
    "azure.workload.identity/use" = "true"
  }

  license_key = var.license_key

  environmentd_version = var.environmentd_version

  force_rollout   = var.force_rollout
  request_rollout = var.request_rollout

  issuer_ref = var.use_self_signed_cluster_issuer ? {
    name = "${var.name_prefix}-root-ca"
    kind = "ClusterIssuer"
  } : null

  depends_on = [
    azurerm_kubernetes_cluster.aks,
    azurerm_postgresql_flexible_server.postgres,
    module.storage,
    module.self_signed_cluster_issuer,
    module.operator,
    module.materialize_nodepool,
  ]
}

# -----------------------------------------------------------------------------
# Load Balancers
# -----------------------------------------------------------------------------
# State path: module.load_balancers.*
#
# MIGRATION: the old module used for_each; auto-migrate.py drops the key.

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

# -----------------------------------------------------------------------------
# CoreDNS (commented out, not in the old setup)
# -----------------------------------------------------------------------------
# MIGRATION: AKS manages CoreDNS by default. Uncomment after migration is
# verified to manage it with Terraform.
#
# module "coredns" {
#   source          = "../../../kubernetes/modules/coredns"
#   node_selector   = {}
#   kubeconfig_data = azurerm_kubernetes_cluster.aks.kube_config_raw
#   depends_on = [
#     azurerm_kubernetes_cluster.aks,
#   ]
# }

# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------

locals {
  materialize_instance_namespace = var.materialize_instance_namespace
  materialize_instance_name      = var.materialize_instance_name

  # MIGRATION: matches the old module's common_labels. They are node labels on
  # the materialize nodepool, so changing them rotates the node pool.
  common_labels = merge(var.tags, {
    managed_by = "terraform"
    module     = "materialize"
  })

  # MIGRATION: must match the old module's URL exactly.
  metadata_backend_url = format(
    "postgres://%s:%s@%s/%s?sslmode=require",
    var.database_username,
    var.old_db_password,
    azurerm_postgresql_flexible_server.postgres.fqdn,
    var.database_name
  )

  # MIGRATION: the old URL appended ?{sas_token}; auth is now via workload identity.
  persist_backend_url = format(
    "%s%s",
    module.storage.primary_blob_endpoint,
    module.storage.container_name,
  )
}
