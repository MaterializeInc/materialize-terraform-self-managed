resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "cert_manager" {
  # cert-manager is a singleton resource for the cluster,
  # so not using name prefixes here.
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

  # One ServiceMonitor across the controller, webhook and cainjector. The
  # chart's metrics Services exist regardless; it does not check for the
  # monitoring.coreos.com API before rendering the monitor.
  set {
    name  = "prometheus.servicemonitor.enabled"
    value = var.enable_service_monitor
  }

  # Annotations on cert-manager's Kubernetes service account, which is how a
  # DNS-01 solver gets a cloud identity (GKE Workload Identity, IRSA). Values
  # are set as strings so that one such as "true" stays a string.
  dynamic "set" {
    for_each = var.service_account_annotations
    content {
      name  = "serviceAccount.annotations.${replace(set.key, ".", "\\.")}"
      value = set.value
      type  = "string"
    }
  }

  # Labels on the controller pods, the ones that solve ACME challenges. Azure
  # Workload Identity selects pods by the azure.workload.identity/use label.
  dynamic "set" {
    for_each = var.pod_labels
    content {
      name  = "podLabels.${replace(set.key, ".", "\\.")}"
      value = set.value
      type  = "string"
    }
  }

  # Add node selectors for cert-manager pods if provided
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

  # Add tolerations for cert-manager pods if provided
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

