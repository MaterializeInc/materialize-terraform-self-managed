# Metrics Server module for Kubernetes
# Required for the Materialize Console to display cluster metrics
# https://github.com/kubernetes-sigs/metrics-server

resource "kubernetes_namespace" "metrics_server" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

locals {
  namespace = var.create_namespace ? kubernetes_namespace.metrics_server[0].metadata[0].name : var.namespace
}

resource "helm_release" "metrics_server" {
  name       = var.release_name
  namespace  = local.namespace
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.chart_version

  dynamic "set" {
    for_each = var.skip_tls_verification ? [1] : []
    content {
      name  = "args[0]"
      value = "--kubelet-insecure-tls"
    }
  }

  set {
    name  = "metrics.enabled"
    value = var.metrics_enabled
  }

  dynamic "set" {
    for_each = var.node_selector
    content {
      name  = "nodeSelector.${set.key}"
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
    kubernetes_namespace.metrics_server
  ]
}
