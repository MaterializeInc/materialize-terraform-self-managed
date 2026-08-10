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
#   * There are no container lifecycle rules, and no variables to configure
#     them — unlike AWS and GCP, which take `logs_retention_days`,
#     `metrics_retention_days`, and `enable_bucket_versioning`. Loki and Thanos
#     each enforce their own retention, so nothing is unbounded, but Azure has
#     neither the retention backstop the other two clouds offer nor blob
#     versioning for recovery. Adding an `azurerm_storage_management_policy`
#     here is tracked separately; if it lands, note that Thanos keeps blocks per
#     downsampling resolution (raw / 5m / 1h), so a policy deleting sooner than
#     it expects removes blocks the compactor still references.
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
#
# Not truncated to 24 here: `var.prefix` is validated so that the whole name
# fits, because a `substr` would trim from the right and eat the very suffix
# that makes the name unique.
resource "azurerm_storage_account" "telemetry" {
  name                = replace("${var.prefix}mzmon${random_string.unique.result}", "-", "")
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
  #
  # The `/` in the tag name is why this module floors at Terraform 1.10. Before
  # that fix, Terraform truncated the ref at the first slash and treated the rest
  # as a subdirectory, failing the clone with `pathspec 'materialize-monitoring'
  # did not match` (hashicorp/terraform#35552). See versions.tf.
  #
  # v0.13.0 is where `grafana_database_*` and the chart's `grafana.ingress` /
  # `grafana.service` values land. This branch does not plan against v0.12.0.
  source = "github.com/MaterializeInc/materialize-monitoring//terraform/modules/materialize-monitoring?ref=materialize-monitoring/v0.15.0"

  namespace        = var.namespace
  create_namespace = var.create_namespace

  chart_version = var.chart_version

  # Null on any of these means "use the monitoring module's own default": each
  # is declared `nullable = false` with a default there, and Terraform
  # substitutes the default when a caller passes null. None of the three is
  # reachable through `additional_values`, so without forwarding them a mirrored
  # registry or a cluster that already owns the CRDs has no way through.
  chart_registry         = var.chart_registry
  enable_monitoring_crds = var.enable_monitoring_crds
  install_timeout        = var.install_timeout

  sizing        = var.sizing
  node_selector = var.node_selector
  tolerations   = var.tolerations
  storage_class = var.storage_class

  materialize_instance_namespace = var.materialize_instance_namespace
  materialize_operator_namespace = var.materialize_operator_namespace
  install_metrics_server         = var.install_metrics_server

  grafana_admin_password = var.grafana_admin_password

  # Explicit rather than inferred from host/password: both are computed here — an
  # instance endpoint and a generated password — so the module cannot decide
  # whether they exist at plan time. These two conditions are plan-known.
  grafana_database_enabled                = local.grafana_database_creating || var.grafana_database_host != null
  grafana_database_manage_password_secret = local.grafana_database_creating || var.grafana_database_password != null

  grafana_database_host     = local.grafana_database_host
  grafana_database_port     = local.grafana_database_port
  grafana_database_name     = var.grafana_database_name
  grafana_database_user     = var.grafana_database_user
  grafana_database_password = local.grafana_database_effective_password
  grafana_database_ssl_mode = var.grafana_database_ssl_mode

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

  # Load-balancer values ahead of the caller's, so `additional_values` still
  # overrides anything computed here.
  additional_values = concat(local.grafana_load_balancer_values, var.additional_values)

  depends_on = [
    azurerm_role_assignment.telemetry,
    azurerm_federated_identity_credential.telemetry,
  ]
}

# ==============================================================================
# Grafana state database
# ==============================================================================
# Reuses this repo's own `database` module rather than an inline
# `azurerm_postgresql_flexible_server`, so Grafana's server gets the same
# backup, storage, and private-networking opinions the Materialize database has.
#
# Grafana connects as the server's administrator. On a Flexible Server that is
# not a shortcut but the only option: there is no ARM resource for creating a
# PostgreSQL role, and Grafana needs DDL on its own database to migrate at
# startup. A dedicated server is what keeps that from meaning anything wider.

resource "random_password" "grafana_database" {
  count = var.grafana_database != null && var.grafana_database_password == null ? 1 : 0

  length = 32
  # Flexible Server rejects several punctuation classes in an administrator
  # password, and Grafana reads this out of a mounted file that operators also
  # paste into psql. Alphanumeric avoids both problems.
  special = false
}

module "grafana_database" {
  count  = var.grafana_database == null ? 0 : 1
  source = "../database"

  resource_group_name = var.resource_group_name
  location            = var.location
  prefix              = "${var.prefix}-mzmon-grafana"

  subnet_id           = var.grafana_database.subnet_id
  private_dns_zone_id = var.grafana_database.private_dns_zone_id

  sku_name              = var.grafana_database.sku_name
  postgres_version      = var.grafana_database.postgres_version
  storage_mb            = var.grafana_database.storage_mb
  backup_retention_days = var.grafana_database.backup_retention_days

  administrator_login    = var.grafana_database_user
  administrator_password = local.grafana_database_password

  databases = [{ name = var.grafana_database_name }]

  tags = merge(var.tags, { Backend = "grafana" })
}

locals {
  grafana_database_creating = var.grafana_database != null

  # A caller-supplied password wins in both modes; the random one only fills the
  # gap when this module creates the instance and was given none.
  #
  # Not `coalesce`: it errors when every argument is null, which is the default
  # install — no database and no password — so it failed the plan on the one path
  # that has nothing to decide. Null here means "no password", which is what the
  # module's own gates are for.
  grafana_database_password = (
    var.grafana_database_password != null
    ? var.grafana_database_password
    : one(random_password.grafana_database[*].result)
  )

  grafana_database_host = local.grafana_database_creating ? (
    module.grafana_database[0].server_fqdn
  ) : var.grafana_database_host

  grafana_database_port = local.grafana_database_creating ? 5432 : var.grafana_database_port

  grafana_database_effective_password = (
    local.grafana_database_creating ? local.grafana_database_password : var.grafana_database_password
  )
}

# ==============================================================================
# Grafana load balancer
# ==============================================================================

locals {
  grafana_scheme = try(var.grafana_load_balancer.tls, false) ? "https" : "http"

  grafana_service_annotations = var.grafana_load_balancer == null ? {} : merge(
    var.grafana_load_balancer.internal ? {
      "service.beta.kubernetes.io/azure-load-balancer-internal" = "true"
    } : {},
    var.grafana_load_balancer.annotations,
  )

  grafana_load_balancer_values = var.grafana_load_balancer == null ? [] : [yamlencode({
    grafana = merge(
      {
        service = {
          type                     = "LoadBalancer"
          annotations              = local.grafana_service_annotations
          loadBalancerSourceRanges = var.grafana_load_balancer.ingress_cidr_blocks
        }
      },
      var.grafana_load_balancer.host == null ? {} : {
        "grafana.ini" = merge(
          {
            # Grafana builds share links, alert notification links, and OAuth
            # redirect URIs from this. All three break silently when it
            # disagrees with the host users actually reach.
            server = { root_url = "${local.grafana_scheme}://${var.grafana_load_balancer.host}" }
          },
          local.grafana_scheme != "https" ? {} : {
            # Only once TLS is real: set without it the session cookie is never
            # sent and nobody can log in.
            security = { cookie_secure = true }
          },
        )
      },
    )
  })]
}

# The load balancer's own address, so `grafana_url` can name where Grafana
# actually answers rather than falling back to the in-cluster Service whenever no
# hostname was supplied.
#
# A data source rather than a resource attribute: the Service is created by Helm
# inside the monitoring module, so Terraform has no handle on it. Read after that
# module, and tolerant of an address that is not assigned yet — the cloud
# provisions the load balancer asynchronously, so the first apply can complete
# before an IP exists. `grafana_url` degrades to the in-cluster name in that
# window, and the next plan picks the address up.
data "kubernetes_service" "grafana" {
  count = var.grafana_load_balancer == null ? 0 : 1

  metadata {
    # The chart pins `grafana.fullnameOverride`, so the name is static.
    name      = "grafana"
    namespace = var.namespace
  }

  depends_on = [module.monitoring]
}

locals {
  # GCP and Azure hand out an IP; the `hostname` branch is there because a
  # cloud-specific annotation can produce one instead.
  grafana_load_balancer_address = one([
    for ing in try(data.kubernetes_service.grafana[0].status[0].load_balancer[0].ingress, []) :
    coalesce(try(ing.hostname, null), try(ing.ip, null))
    if coalesce(try(ing.hostname, null), try(ing.ip, null), "") != ""
  ])
}
