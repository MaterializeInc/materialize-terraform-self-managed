resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "cert_manager" {
  # Singleton per cluster, so no name prefix.
  name       = "cert-manager"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.chart_version
  timeout    = var.install_timeout

  set {
    name  = "crds.enabled"
    value = "true"
  }

  # One ServiceMonitor for the controller, webhook and cainjector. The chart
  # does not check for the monitoring.coreos.com API first.
  set {
    name  = "prometheus.servicemonitor.enabled"
    value = var.enable_service_monitor
  }

  dynamic "set" {
    for_each = var.node_selector
    content {
      name  = "nodeSelector.${replace(set.key, ".", "\\.")}"
      value = set.value
    }
  }
  dynamic "set" {
    for_each = var.node_selector
    content {
      name  = "webhook.nodeSelector.${replace(set.key, ".", "\\.")}"
      value = set.value
    }
  }
  dynamic "set" {
    for_each = var.node_selector
    content {
      name  = "cainjector.nodeSelector.${replace(set.key, ".", "\\.")}"
      value = set.value
    }
  }

  dynamic "set" {
    for_each = length(var.tolerations) > 0 ? range(length(var.tolerations)) : []
    content {
      name  = "tolerations[${set.value}].key"
      value = var.tolerations[set.value].key
    }
  }

  dynamic "set" {
    for_each = length(var.tolerations) > 0 ? range(length(var.tolerations)) : []
    content {
      name  = "tolerations[${set.value}].operator"
      value = var.tolerations[set.value].operator
    }
  }

  dynamic "set" {
    for_each = length(var.tolerations) > 0 ? [
      for i, toleration in var.tolerations : i
      if toleration.value != null
    ] : []
    content {
      name  = "tolerations[${set.value}].value"
      value = var.tolerations[set.value].value
    }
  }

  dynamic "set" {
    for_each = length(var.tolerations) > 0 ? range(length(var.tolerations)) : []
    content {
      name  = "tolerations[${set.value}].effect"
      value = var.tolerations[set.value].effect
    }
  }

  depends_on = [
    kubernetes_namespace.cert_manager,
  ]
}

