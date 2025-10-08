

locals {
  default_helm_values = {
    operator = {
      args = {
        enableLicenseKeyChecks = var.enable_license_key_checks
      }
      image = var.orchestratord_version == null ? {} : {
        tag = var.orchestratord_version
      },
      cloudProvider = {
        type   = "azure"
        region = var.location
      }
      clusters = {
        swap_enabled = var.swap_enabled
      }
      # Node selector and tolerations for operator pods
      nodeSelector = var.operator_node_selector
      tolerations  = var.tolerations
    }

    # Materialize workload configurations
    environmentd = {
      nodeSelector = var.instance_node_selector
      tolerations  = var.instance_pod_tolerations
    }
    clusterd = {
      nodeSelector = var.instance_node_selector
      tolerations  = var.instance_pod_tolerations
    }
    balancerd = {
      nodeSelector = var.instance_node_selector
      tolerations  = var.instance_pod_tolerations
    }
    console = {
      nodeSelector = var.instance_node_selector
      tolerations  = var.instance_pod_tolerations
    }

    observability = {
      podMetrics = {
        enabled = true
      }
    }
  }
}

resource "kubernetes_namespace" "materialize" {
  metadata {
    name = var.operator_namespace
  }
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.monitoring_namespace
  }
}

resource "helm_release" "materialize_operator" {
  name      = var.name_prefix
  namespace = kubernetes_namespace.materialize.metadata[0].name

  repository = var.use_local_chart ? null : var.helm_repository
  chart      = var.helm_chart
  version    = var.use_local_chart ? null : var.operator_version

  values = [
    yamlencode(provider::deepmerge::mergo(local.default_helm_values, var.helm_values))
  ]

  depends_on = [kubernetes_namespace.materialize]
}

# Install the metrics-server for monitoring
# Required for the Materialize Console to display cluster metrics
# Defaults to false because AKS provides metrics-server by default
# TODO: we should rather rely on AKS metrics-server instead of installing our own, confirm with team and get rid of this helm release
resource "helm_release" "metrics_server" {
  count = var.install_metrics_server ? 1 : 0

  name       = "${var.name_prefix}-metrics-server"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_version

  # Configuration values based on metrics_server_values
  dynamic "set" {
    for_each = var.metrics_server_values.skip_tls_verification ? [1] : []
    content {
      name  = "args[0]"
      value = "--kubelet-insecure-tls"
    }
  }

  set {
    name  = "metrics.enabled"
    value = var.metrics_server_values.metrics_enabled
  }

  # Add node selectors for metrics-server pods if provided
  dynamic "set" {
    for_each = var.operator_node_selector
    content {
      name  = "nodeSelector.${set.key}"
      value = set.value
    }
  }

  # Add tolerations for metrics-server pods if provided
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
    kubernetes_namespace.monitoring
  ]
}
