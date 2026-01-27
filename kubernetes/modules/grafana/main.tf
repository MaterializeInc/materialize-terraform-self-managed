# Grafana module for Materialize observability
# Uses grafana/grafana Helm chart with Materialize dashboards

resource "kubernetes_namespace" "grafana" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

# ensure storage class exists is passed.
data "kubernetes_storage_class" "grafana" {
  count = var.storage_class != null ? 1 : 0
  metadata {
    name = var.storage_class
  }
}

locals {
  # Dashboard URLs from Materialize repository
  # Source: https://github.com/MaterializeInc/materialize/tree/self-managed-docs/v25.2/doc/user/data/monitoring/grafana_dashboards

  dashboards = {
    environment_overview = {
      name    = "environment-overview"
      content = file("${path.module}/environment_overview_dashboard.json")
    }
    freshness_overview = {
      name    = "freshness-overview"
      content = file("${path.module}/freshness_overview_dashboard.json")
    }
  }
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
    "${each.value.name}.json" = each.value.content
  }
}

resource "random_password" "grafana_admin" {
  count            = var.admin_password == null ? 1 : 0
  length           = 16
  special          = true
  override_special = "@$%^()_+-="
}

locals {
  admin_password = var.admin_password != null ? var.admin_password : random_password.grafana_admin[0].result

  helm_values = {
    adminPassword = local.admin_password

    persistence = {
      enabled      = true
      size         = var.storage_size
      storageClass = var.storage_class
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
        enabled           = true
        label             = "grafana_dashboard"
        labelValue        = "1"
        searchNamespace   = var.namespace
        folder            = "/var/lib/grafana/dashboards"
        defaultFolderName = "materialize"
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

  depends_on = [
    kubernetes_config_map.dashboards,
    data.kubernetes_storage_class.grafana,
  ]
}
