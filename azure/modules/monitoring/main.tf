# Deploys the `materialize-monitoring` stack on AKS: Grafana, metrics via Thanos,
# logs via Loki, and the Alloy pipeline. This module owns the Azure side (one
# storage account with a container, user-assigned identity, and federated
# credential per backend) and delegates everything in the cluster to the
# cloud-agnostic module shipped with the chart, so no Helm value paths live here.
#
# Operational notes:
#
#   * The cluster needs workload identity and the OIDC issuer enabled
#     (`workload_identity_enabled`, `oidc_issuer_enabled`); the `aks` module sets both.
#   * One identity per backend, each scoped to its own container, so neither can
#     read the other's data. Same as AWS and GCP.
#   * The webhook only mutates pods labelled `azure.workload.identity/use`. The
#     monitoring module adds it via `loki.podLabels` and, since Thanos has no
#     `podLabels`, `thanos.global.commonLabels`.
#   * `provider_metrics` gives the Alloy gateway its own identity, used only to
#     read Azure Monitor. The monitoring module labels the gateway pods for the
#     webhook whenever its ServiceAccount carries a client ID.
#   * The `monitoring-crds` module creates the `monitoring` namespace and the
#     CRDs, so `create_namespace` defaults to false and the examples pass
#     `enable_monitoring_crds = false`. Pass its `namespace` output as
#     `namespace` (or keep a `depends_on`) or the release can race the namespace.
#   * Unlike AWS and GCP there are no container lifecycle rules, retention
#     backstop, or blob versioning; Loki and Thanos enforce their own retention.
#     A future `azurerm_storage_management_policy` must not delete sooner than
#     Thanos expects: it keeps blocks per downsampling resolution (raw / 5m / 1h).
#
# One storage account with a container per backend: role assignments scope to a
# container, so isolation holds without a second account, and account names
# (globally unique, 3-24 alphanumeric characters) are awkward enough to want one.

locals {
  # Must match the chart's ServiceAccount names for the federated credentials.
  # The monitoring module outputs them too, but reading that would be a dependency cycle.
  service_accounts = {
    loki   = "loki"
    thanos = "thanos-thanos"
  }

  containers = {
    loki   = var.loki_container_name
    thanos = var.thanos_container_name
  }

  # Not in the map above: the gateway reads Azure Monitor, not a container.
  gateway_service_account  = "alloy-gateway"
  provider_metrics_enabled = var.provider_metrics != null
}

# ==============================================================================
# Storage
# ==============================================================================

resource "random_string" "unique" {
  length  = 6
  special = false
  upper   = false
}

# Account names are globally unique, lowercase alphanumeric, and at most 24
# characters, hence the suffix and the `replace`. Not truncated: `var.prefix` is
# validated so the name fits, since `substr` would cut the uniqueness suffix.
resource "azurerm_storage_account" "telemetry" {
  name                = replace("${var.prefix}mzmon${random_string.unique.result}", "-", "")
  resource_group_name = var.resource_group_name
  location            = var.location

  # Standard, not Premium like the Materialize persist account: telemetry is large
  # sequential writes and range reads, so throughput beats latency, and Premium
  # costs several times more for data held for months.
  account_tier             = "Standard"
  account_replication_type = var.account_replication_type
  account_kind             = "StorageV2"
  min_tls_version          = "TLS1_2"

  # Both backends authenticate as an identity, so shared keys stay off.
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

# Scoped to the backend's own container, not the account. Contributor, not
# Owner: neither backend manages the container or its ACLs.
resource "azurerm_role_assignment" "telemetry" {
  for_each = local.service_accounts

  scope                = azurerm_storage_container.telemetry[each.key].resource_manager_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.telemetry[each.key].principal_id
}

# Trusts the in-cluster ServiceAccount's projected token. The audience is fixed by
# Entra's token-exchange endpoint.
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
# Provider metrics: what the gateway pulls
# ==============================================================================
# The gateway gets its own identity: it reads Azure Monitor and no container, and
# neither backend reads Azure Monitor.

resource "azurerm_user_assigned_identity" "gateway" {
  count = local.provider_metrics_enabled ? 1 : 0

  name                = "${var.prefix}-mzmon-gateway"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}

resource "azurerm_federated_identity_credential" "gateway" {
  count = local.provider_metrics_enabled ? 1 : 0

  name                = "${var.prefix}-mzmon-gateway"
  resource_group_name = var.resource_group_name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.gateway[0].id
  subject             = "system:serviceaccount:${var.namespace}:${local.gateway_service_account}"
}

# Named, never discovered: the chart pulls exactly these resources. This module's
# own resources join the caller's unless `include_monitoring_resources` is false.
#
# Keyed by position, not ID, so keys are plan-known even for resources created in
# the same apply.

locals {
  provider_metrics_postgres = local.provider_metrics_enabled ? merge(
    { for i, id in var.provider_metrics.postgres_server_ids : "postgres-${i}" => id },
    var.provider_metrics.include_monitoring_resources && local.create_grafana_database ? { grafana = module.grafana_database[0].server_id } : {},
  ) : {}

  provider_metrics_storage = local.provider_metrics_enabled ? merge(
    { for i, id in var.provider_metrics.storage_account_ids : "storage-${i}" => id },
    var.provider_metrics.include_monitoring_resources ? { telemetry = azurerm_storage_account.telemetry.id } : {},
  ) : {}

  # Each cluster plus its node resource group, where the pull finds the node pool
  # scale sets via a Resource Graph join. AKS creates that group in the cluster's
  # subscription.
  provider_metrics_aks = local.provider_metrics_enabled ? merge(
    { for i, c in var.provider_metrics.aks_clusters : "aks-${i}" => c.id },
    { for i, c in var.provider_metrics.aks_clusters : "aks-${i}-nodes" => "/subscriptions/${split("/", c.id)[2]}/resourceGroups/${c.node_resource_group}" },
  ) : {}

  # The subscription this module deploys into. The chart queries one, so every
  # listed resource has to be in it; the grants below refuse any that is not.
  subscription_id = split("/", azurerm_storage_account.telemetry.id)[2]

  # Optional fields are omitted rather than set to null, so the chart's own
  # defaults survive. A resource ID's ninth segment is its name.
  provider_metrics_values = local.provider_metrics_enabled ? [yamlencode({
    pipeline = {
      metrics = {
        provider = {
          azure = merge(
            {
              enabled        = true
              subscriptionId = local.subscription_id
              postgres       = { servers = [for id in values(local.provider_metrics_postgres) : split("/", id)[8]] }
              blob           = { storageAccounts = [for id in values(local.provider_metrics_storage) : split("/", id)[8]] }
              aks            = { clusters = [for c in var.provider_metrics.aks_clusters : split("/", c.id)[8]] }
            },
            var.provider_metrics.scrape_interval == null ? {} : { scrapeInterval = var.provider_metrics.scrape_interval },
            var.provider_metrics.importance == null ? {} : { metricImportance = var.provider_metrics.importance },
          )
        }
      }
    }
  })] : []
}

# Monitoring Reader is `*/read` at its scope: configuration and metrics, but not
# keys (actions) or blobs (data actions). Azure Monitor reads scope to a resource,
# so nothing wider is granted, except an AKS node resource group, granted whole
# because AKS creates and replaces the scale sets in it.
resource "azurerm_role_assignment" "gateway_monitoring_reader" {
  for_each = merge(local.provider_metrics_postgres, local.provider_metrics_storage, local.provider_metrics_aks)

  scope                = each.value
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_user_assigned_identity.gateway[0].principal_id

  lifecycle {
    precondition {
      condition     = lower(split("/", each.value)[2]) == lower(local.subscription_id)
      error_message = "provider_metrics lists ${each.value}, which is outside the subscription this module deploys into. The chart queries one subscription, so the pull would never find it."
    }
  }
}

# ==============================================================================
# The stack
# ==============================================================================

module "monitoring" {
  # Pinned to a released tag. The module reads its chart version from the chart
  # beside it, so this ref alone sets the chart version.
  #
  # To develop against an unreleased module, use a *relative* path to a local
  # checkout (`../../../../materialize-monitoring/terraform/modules/materialize-monitoring`).
  # An absolute path copies the module without the chart, and sizing profiles break.
  #
  # The `/` in the tag needs Terraform >= 1.10 (hashicorp/terraform#35552).
  source = "github.com/MaterializeInc/materialize-monitoring//terraform/modules/materialize-monitoring?ref=materialize-monitoring/v0.30.0"

  namespace        = var.namespace
  create_namespace = var.create_namespace

  chart_version = var.chart_version

  # Null uses the monitoring module's default (they are `nullable = false` there).
  # None can be set through `additional_values`, so they must be forwarded.
  chart_registry         = var.chart_registry
  enable_monitoring_crds = var.enable_monitoring_crds
  install_timeout        = var.install_timeout

  sizing        = var.sizing
  node_selector = var.node_selector
  tolerations   = var.tolerations
  storage_class = var.storage_class
  min_zones     = var.min_zones

  materialize_instance_namespace = var.materialize_instance_namespace
  materialize_operator_namespace = var.materialize_operator_namespace
  install_metrics_server         = var.install_metrics_server

  grafana_admin_password = var.grafana_admin_password

  # In-cluster TLS defaults to on here rather than in the monitoring module: every
  # example in this repo installs cert-manager, other consumers may not.
  certificates_enabled       = var.certificates_enabled
  internal_tls               = coalesce(var.internal_tls, var.certificates_enabled ? "authenticate" : "off")
  issuer_ref                 = var.issuer_ref
  internal_issuer_ref        = var.internal_issuer_ref
  grafana_external_dns_names = var.grafana_external_dns_names
  certificate_duration       = var.certificate_duration
  certificate_renew_before   = var.certificate_renew_before

  # Explicit, not inferred from host/password: those can be unknown at plan time
  # (server FQDN, generated password), but these conditions are plan-known.
  grafana_database_enabled                = local.create_grafana_database || var.grafana_database_host != null
  grafana_database_manage_password_secret = local.create_grafana_database || var.grafana_database_password != null

  # TODO: pass the Grafana Service port once the monitoring module accepts one.
  # The chart sets it (`grafana.service.port`, 80) and nothing here sets it on the
  # chart, so they agree by coincidence. In-cluster TLS will move that port.
  #
  # grafana_service_port = 80

  grafana_database_host     = local.grafana_database_host
  grafana_database_port     = local.grafana_database_port
  grafana_database_name     = local.grafana_database_name
  grafana_database_user     = var.grafana_database_user
  grafana_database_password = local.grafana_database_effective_password
  grafana_database_ssl_mode = var.grafana_database_ssl_mode

  object_storage = {
    cloud         = "azure"
    loki_bucket   = azurerm_storage_container.telemetry["loki"].name
    thanos_bucket = azurerm_storage_container.telemetry["thanos"].name

    azure_storage_account = azurerm_storage_account.telemetry.name

    # The Entra webhook reads the client ID from this annotation and resolves the
    # tenant and authority host itself.
    loki_service_account_annotations = {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.telemetry["loki"].client_id
    }
    thanos_service_account_annotations = {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.telemetry["thanos"].client_id
    }
    # Only set when the gateway reads Azure Monitor; it needs no container.
    gateway_service_account_annotations = local.provider_metrics_enabled ? {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.gateway[0].client_id
    } : {}
  }

  # Passed through; the monitoring module validates them and keeps credentials
  # out of the Helm values (they go in the gateway Secret).
  datadog_metrics = var.datadog_metrics
  datadog_api_key = var.datadog_api_key

  otlp_metrics             = var.otlp_metrics
  otlp_auth_header_secrets = var.otlp_auth_header_secrets
  otlp_auth_bearer_token   = var.otlp_auth_bearer_token

  # Passed through; the monitoring module validates them and fails the plan when
  # a receiver reads a key `alerting_receiver_secrets` does not set.
  alert_rules               = var.alert_rules
  alerting                  = var.alerting
  alerting_receiver_secrets = var.alerting_receiver_secrets
  alertmanager_namespace    = var.alertmanager_namespace

  # Computed values first, so `additional_values` overrides them.
  additional_values = concat(local.grafana_load_balancer_values, local.provider_metrics_values, var.additional_values)

  depends_on = [
    azurerm_role_assignment.telemetry,
    azurerm_federated_identity_credential.telemetry,
    azurerm_role_assignment.gateway_monitoring_reader,
    azurerm_federated_identity_credential.gateway,
  ]
}

# ==============================================================================
# Grafana state database
# ==============================================================================
# Uses this repo's `database` module so Grafana's server gets the same backup,
# storage, and private-networking settings as the Materialize database.
# Grafana connects as the administrator: there is no ARM resource for creating a
# PostgreSQL role, and Grafana needs DDL for its startup migrations. A dedicated
# server keeps that from granting anything wider.

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

  administrator_login = var.grafana_database_user
  # Null by default, so the database module generates and owns the password.
  administrator_password = var.grafana_database_password

  databases = [{ name = var.grafana_database_name }]

  tags = merge(var.tags, { Backend = "grafana" })
}

locals {
  create_grafana_database = var.grafana_database != null

  # A caller-supplied password wins; otherwise use the one the database module
  # generated. Null means no database and no password (the default install).
  grafana_database_password = (
    var.grafana_database_password != null
    ? var.grafana_database_password
    : (local.create_grafana_database ? module.grafana_database[0].administrator_password : null)
  )

  grafana_database_host = local.create_grafana_database ? (
    module.grafana_database[0].server_fqdn
  ) : var.grafana_database_host

  # Read from the database output so destroy removes the release before the database.
  grafana_database_name = local.create_grafana_database ? (
    module.grafana_database[0].databases[var.grafana_database_name].name
  ) : var.grafana_database_name

  grafana_database_port = local.create_grafana_database ? 5432 : var.grafana_database_port

  grafana_database_effective_password = (
    local.create_grafana_database ? local.grafana_database_password : var.grafana_database_password
  )
}

# ==============================================================================
# Grafana load balancer
# ==============================================================================

locals {
  # Always http: an Azure Service load balancer is L4 and terminates no TLS. Setting
  # `security.cookie_secure` without TLS stops the browser sending the session
  # cookie, so nobody can log in. Once something terminates TLS (DEP-195), set
  # `root_url` and `security.cookie_secure` through `additional_values`.
  grafana_scheme = "http"

  grafana_service_annotations = var.grafana_load_balancer == null ? {} : merge(
    var.grafana_load_balancer.internal ? {
      "service.beta.kubernetes.io/azure-load-balancer-internal" = "true"
    } : {},
    var.grafana_load_balancer.annotations,
  )

  grafana_load_balancer_values = var.grafana_load_balancer == null ? [] : [yamlencode({
    grafana = merge(
      {
        service = merge(
          {
            type                     = "LoadBalancer"
            annotations              = local.grafana_service_annotations
            loadBalancerSourceRanges = var.grafana_load_balancer.ingress_cidr_blocks
          },
          # Pre-allocated, so the address is known at plan time without reading
          # the Service back.
          var.grafana_load_balancer.ip == null ? {} : {
            loadBalancerIP = var.grafana_load_balancer.ip
          },
        )
      },
      var.grafana_load_balancer.host == null ? {} : {
        "grafana.ini" = {
          # Share links, alert links, and OAuth redirect URIs are built from this
          # and break silently if it differs from the host users reach.
          server = { root_url = "${local.grafana_scheme}://${var.grafana_load_balancer.host}" }
        }
      },
    )
  })]
}

# Reads the load balancer address so `grafana_url` can use it when no hostname is
# set. A data source because Helm creates the Service. The address is assigned
# asynchronously, so after the first apply `grafana_url` may still show the
# in-cluster name; the next plan picks the address up.
data "kubernetes_service" "grafana" {
  # Skipped when the address was pre-allocated. Both conditions are plan-known.
  count = var.grafana_load_balancer == null || var.grafana_load_balancer.ip != null ? 0 : 1

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
  grafana_load_balancer_address = try(var.grafana_load_balancer.ip, null) != null ? (
    var.grafana_load_balancer.ip
    ) : one([
      for ing in try(data.kubernetes_service.grafana[0].status[0].load_balancer[0].ingress, []) :
      coalesce(try(ing.hostname, null), try(ing.ip, null))
      if coalesce(try(ing.hostname, null), try(ing.ip, null), "") != ""
  ])
}
