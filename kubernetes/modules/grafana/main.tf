# Grafana module for Materialize observability
# WARNING: unstable as of June 2026 (major changes incoming soon!)

resource "kubernetes_namespace" "grafana" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

locals {
  # Source: https://materializeinc.github.io/materialize-monitoring/dashboards/grafana/

  dashboards = {
    environment_overview = {
      name    = "mz-mon-env-top"
      content = file("${path.module}/env-top.json")
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
            jsonData = {
              # Must match prometheus scrape to avoid having too low of a $__rate_interval
              timeInterval = "60s"
            }
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
  repository = var.chart_repository
  chart      = "grafana"
  version    = var.chart_version
  timeout    = var.install_timeout

  values = [yamlencode(local.helm_values)]

  depends_on = [
    kubernetes_config_map.dashboards,
  ]
}
