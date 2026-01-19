# Prometheus module for Materialize observability
# Uses prometheus-community/prometheus Helm chart with Materialize scrape configs

resource "kubernetes_namespace" "prometheus" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

locals {
  namespace = var.create_namespace ? kubernetes_namespace.prometheus[0].metadata[0].name : var.namespace

  # Source: https://github.com/MaterializeInc/materialize/blob/main/doc/user/data/self_managed/monitoring/prometheus.yml
  materialize_scrape_config = yamldecode(file("${path.module}/prometheus.yml"))

  helm_values = {
    server = {
      retention = "${var.retention_days}d"

      persistentVolume = {
        enabled = true
        size    = var.storage_size
        accessModes = [
          # EBS only supports ReadWriteOnce (single node attachment)
          "ReadWriteOnce"
        ]
        storageClass = var.storage_class
      }

      global = local.materialize_scrape_config.global

      resources = {
        requests = {
          cpu    = var.server_resources.requests.cpu
          memory = var.server_resources.requests.memory
        }
        limits = {
          cpu    = var.server_resources.limits.cpu
          memory = var.server_resources.limits.memory
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
    }

    # Disable components not needed for basic monitoring
    alertmanager = {
      enabled = false
    }
    kube-state-metrics = {
      enabled = true
    }
    prometheus-node-exporter = {
      enabled = true
    }
    prometheus-pushgateway = {
      enabled = false
    }

    scrapeConfigs = local.materialize_scrape_config.scrape_configs
  }
}

resource "helm_release" "prometheus" {
  name       = "prometheus"
  namespace  = local.namespace
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"
  version    = var.chart_version
  timeout    = var.install_timeout

  values = [yamlencode(local.helm_values)]

  depends_on = [kubernetes_namespace.prometheus]
}
