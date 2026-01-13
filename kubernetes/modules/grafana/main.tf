# Grafana module for Materialize observability
# Uses grafana/grafana Helm chart with Materialize dashboards

resource "kubernetes_namespace" "grafana" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

locals {
  # Dashboard URLs from Materialize repository
  # Source: https://github.com/MaterializeInc/materialize/tree/self-managed-docs/v25.2/doc/user/data/monitoring/grafana_dashboards
  dashboard_base_url = "https://raw.githubusercontent.com/MaterializeInc/materialize/self-managed-docs/v25.2/doc/user/data/monitoring/grafana_dashboards"

  dashboards = {
    environment_overview = {
      name = "environment-overview"
      url  = "${local.dashboard_base_url}/environment_overview_dashboard.json"
    }
    freshness_overview = {
      name = "freshness-overview"
      url  = "${local.dashboard_base_url}/freshness_overview_dashboard.json"
    }
  }
}

# Fetch Materialize dashboards from GitHub
data "http" "dashboards" {
  for_each = local.dashboards

  url = each.value.url

}

# Create ConfigMaps for Grafana dashboard sidecar to pick up
resource "kubernetes_config_map" "dashboards" {
  for_each = local.dashboards

  metadata {
    name      = "grafana-dashboard-${each.value.name}"
    namespace = var.namespace
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "${each.value.name}.json" = data.http.dashboards[each.key].response_body
  }
}

locals {
  helm_values = {
    adminPassword = var.admin_password

    persistence = {
      enabled = true
      size    = var.storage_size
    }

    resources = {
      requests = {
        cpu    = var.resources.requests.cpu
        memory = var.resources.requests.memory
      }
      limits = {
        cpu    = var.resources.limits.cpu
        memory = var.resources.limits.memory
      }
    }

    nodeSelector = var.node_selector
    tolerations = [
      for t in var.tolerations : {
        key      = t.key
        operator = t.operator
        value    = t.value
        effect   = t.effect
      }
    ]

    # Configure Prometheus as default data source
    datasources = {
      "datasources.yaml" = {
        apiVersion = 1
        datasources = [
          {
            name      = "Prometheus"
            type      = "prometheus"
            url       = var.prometheus_url
            access    = "proxy"
            isDefault = true
          }
        ]
      }
    }

    # Enable sidecar for dashboard provisioning from ConfigMaps
    sidecar = {
      dashboards = {
        enabled          = true
        label            = "grafana_dashboard"
        labelValue       = "1"
        searchNamespace  = "ALL"
        folderAnnotation = "grafana_folder"
        provider = {
          foldersFromFilesStructure = true
        }
      }
    }

    # Dashboard providers configuration
    dashboardProviders = {
      "dashboardproviders.yaml" = {
        apiVersion = 1
        providers = [
          {
            name            = "default"
            orgId           = 1
            folder          = "Materialize"
            type            = "file"
            disableDeletion = false
            editable        = true
            options = {
              path = "/var/lib/grafana/dashboards/default"
            }
          }
        ]
      }
    }
  }
}

resource "helm_release" "grafana" {
  name       = "grafana"
  namespace  = var.namespace
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = var.chart_version
  timeout    = var.install_timeout

  values = [yamlencode(local.helm_values)]

  depends_on = [kubernetes_config_map.dashboards]
}
