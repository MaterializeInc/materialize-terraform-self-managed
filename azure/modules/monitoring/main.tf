# Deploys the `materialize-monitoring` observability stack on AKS: Grafana
# dashboards, Prometheus-compatible metrics via Thanos, logs via Loki, and the
# Alloy collection pipeline.
#
# This module owns the Azure side — one storage account with a container per
# backend, a user-assigned identity per backend, and the federated credentials
# that let the in-cluster service accounts exchange their projected tokens — and
# delegates everything inside the cluster to the cloud-agnostic module that ships
# alongside the chart in the `materialize-monitoring` repository. Nothing here
# names a Helm value path; that knowledge lives next to the chart.
#
# Replaces the previous `kubernetes/modules/prometheus` and
# `kubernetes/modules/grafana`, which vendored a point-in-time dashboard copy and
# a legacy scrape config, collected metrics only, and ran a single Prometheus on
# a ReadWriteOnce volume with 15 days of retention.
#
# Operational notes:
#
#   * Workload identity and the OIDC issuer must both be enabled on the cluster
#     (`workload_identity_enabled`, `oidc_issuer_enabled`). The `aks` module sets
#     both.
#   * One identity per backend rather than the cluster's shared identity: Loki and
#     Thanos each get a container and a role assignment scoped to it, so neither
#     can read the other's data. That mirrors the AWS and GCP wrappers.
#   * The webhook only mutates pods labelled `azure.workload.identity/use`, and
#     the monitoring module applies that label — via `loki.podLabels` for Loki and
#     `thanos.global.commonLabels` for Thanos, which has no `podLabels` of its
#     own. The federated credentials below are what the projected tokens exchange
#     against.
#   * The `monitoring` namespace is created by the operator module in the
#     supported topology, so `create_namespace` defaults to false. Keep a
#     `depends_on` for the operator or the release can race the namespace.
#   * Container lifecycle rules are off by default. Loki and Thanos both enforce
#     their own retention, and Thanos keeps blocks per downsampling resolution
#     (raw / 5m / 1h) — a lifecycle rule deleting sooner removes blocks the
#     compactor still references.
#
# One storage account with a container per backend rather than an account per
# backend: role assignments scope to a container, so isolation is preserved
# without paying for two accounts, and Azure's account-name constraints (globally
# unique, 3-24 chars, alphanumeric) are awkward enough to want only one.

locals {
  # The chart renders deterministic ServiceAccount names, and the federated
  # credential subjects below have to match them exactly. The monitoring module
  # emits the resolved subjects as an output; these are the same names, needed
  # here before that module exists — passing them the other way would close a
  # dependency cycle.
  service_accounts = {
    loki   = "loki"
    thanos = "thanos-thanos"
  }

  containers = {
    loki   = var.loki_container_name
    thanos = var.thanos_container_name
  }
}

# ==============================================================================
# Storage
# ==============================================================================

resource "random_string" "unique" {
  length  = 6
  special = false
  upper   = false
}

# Account names are globally unique, lowercase alphanumeric, and capped at 24
# characters — hence the suffix and the `replace`.
resource "azurerm_storage_account" "telemetry" {
  name                = substr(replace("${var.prefix}mzmon${random_string.unique.result}", "-", ""), 0, 24)
  resource_group_name = var.resource_group_name
  location            = var.location

  # Standard/StorageV2 rather than the Premium BlockBlobStorage the Materialize
  # persist account uses: telemetry is written in large sequential blocks and read
  # by range, so throughput matters more than per-operation latency, and Premium
  # costs several times more for capacity we will hold for months.
  account_tier             = "Standard"
  account_replication_type = var.account_replication_type
  account_kind             = "StorageV2"
  min_tls_version          = "TLS1_2"

  # Both backends authenticate as an identity; there is no reason to leave the
  # shared keys usable.
  shared_access_key_enabled = false

  dynamic "network_rules" {
    for_each = length(var.subnets) == 0 ? [] : ["has_subnets"]
    content {
      default_action             = var.network_rules_default_action
      bypass                     = ["AzureServices"]
      virtual_network_subnet_ids = var.subnets
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "telemetry" {
  for_each = local.containers

  name                  = each.value
  storage_account_id    = azurerm_storage_account.telemetry.id
  container_access_type = "private"
}

# ==============================================================================
# Workload identity
# ==============================================================================

resource "azurerm_user_assigned_identity" "telemetry" {
  for_each = local.service_accounts

  name                = "${var.prefix}-mzmon-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}

# Scoped to the one container that backend owns, not the account. Blob Data
# Contributor rather than Owner: both backends read, write, and delete blobs, but
# neither needs to manage the container itself or its ACLs.
resource "azurerm_role_assignment" "telemetry" {
  for_each = local.service_accounts

  scope                = azurerm_storage_container.telemetry[each.key].resource_manager_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.telemetry[each.key].principal_id
}

# Establishes trust between the in-cluster ServiceAccount and the identity. The
# audience is fixed by Entra's token-exchange endpoint and must match the one the
# projected token is minted for.
resource "azurerm_federated_identity_credential" "telemetry" {
  for_each = local.service_accounts

  name                = "${var.prefix}-mzmon-${each.key}"
  resource_group_name = var.resource_group_name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.telemetry[each.key].id
  subject             = "system:serviceaccount:${var.namespace}:${each.value}"
}

# ==============================================================================
# The stack
# ==============================================================================

module "monitoring" {
  # Pinned to a released tag. The module and the chart it installs are one
  # release, and the module reads its chart version out of the chart beside it —
  # so this ref alone names the chart version, with nothing to keep in sync.
  #
  # Developing against an unreleased module: point this at a local checkout
  # (`../../../../materialize-monitoring/terraform/modules/materialize-monitoring`)
  # for the duration. It must stay a *relative* path — an absolute one makes
  # Terraform copy the module without the chart directory beside it, and the
  # sizing profiles stop resolving.
  source = "github.com/MaterializeInc/materialize-monitoring//terraform/modules/materialize-monitoring?ref=materialize-monitoring/v0.12.0"

  namespace        = var.namespace
  create_namespace = var.create_namespace

  chart_version = var.chart_version

  sizing        = var.sizing
  node_selector = var.node_selector
  tolerations   = var.tolerations
  storage_class = var.storage_class

  materialize_instance_namespace = var.materialize_instance_namespace
  materialize_operator_namespace = var.materialize_operator_namespace
  install_metrics_server         = var.install_metrics_server

  grafana_admin_password = var.grafana_admin_password

  object_storage = {
    cloud         = "azure"
    loki_bucket   = azurerm_storage_container.telemetry["loki"].name
    thanos_bucket = azurerm_storage_container.telemetry["thanos"].name

    azure_storage_account = azurerm_storage_account.telemetry.name

    # Each backend's own identity. The Entra webhook reads the client ID from the
    # annotation and resolves the tenant and authority host itself, so nothing
    # else needs threading through.
    loki_service_account_annotations = {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.telemetry["loki"].client_id
    }
    thanos_service_account_annotations = {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.telemetry["thanos"].client_id
    }
  }

  additional_values = var.additional_values

  depends_on = [
    azurerm_role_assignment.telemetry,
    azurerm_federated_identity_credential.telemetry,
  ]
}
