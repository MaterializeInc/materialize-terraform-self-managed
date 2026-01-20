# Base Materialize Operator module
# This module can be used directly for local/kind deployments or wrapped by
# cloud-specific modules (aws, gcp, azure) that provide cloud provider config.

resource "kubernetes_namespace" "materialize" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.operator_namespace
  }
}

resource "kubernetes_namespace" "monitoring" {
  count = var.create_monitoring_namespace ? 1 : 0

  metadata {
    name = var.monitoring_namespace
  }
}

locals {
  operator_namespace   = var.create_namespace ? kubernetes_namespace.materialize[0].metadata[0].name : var.operator_namespace
  monitoring_namespace = var.create_monitoring_namespace ? kubernetes_namespace.monitoring[0].metadata[0].name : var.monitoring_namespace

  # Build cloud provider config only if specified
  cloud_provider_helm_values = var.cloud_provider_config != null ? {
    operator = {
      cloudProvider = var.cloud_provider_config
    }
  } : {}

  # Strip null values from user helm_values BEFORE merging
  # This is necessary because optional() fields in the type definition
  # become null when not specified, which would overwrite defaults
  clean_user_helm_values = {
    for k, v in var.helm_values : k => v if v != null
  }

  # Default helm values (without cloud provider - that's merged separately)
  default_helm_values = {
    observability = {
      podMetrics = {
        enabled = true
      }
    }
    operator = {
      args = {
        enableLicenseKeyChecks = var.enable_license_key_checks
      }
      image = var.orchestratord_version == null ? {} : {
        tag = var.orchestratord_version
      }
      clusters = {
        swap_enabled = var.swap_enabled
      }
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
  }

  # Merge: defaults -> cloud provider config -> user overrides
  merged_helm_values = provider::deepmerge::mergo(
    provider::deepmerge::mergo(local.default_helm_values, local.cloud_provider_helm_values),
    local.clean_user_helm_values
  )

  # Strip null values from helm values to avoid Helm template errors
  # Helm templates expect missing keys, not explicit null values
  clean_helm_values = {
    for k, v in local.merged_helm_values : k => v if v != null
  }
}

resource "helm_release" "materialize_operator" {
  name      = var.name_prefix
  namespace = local.operator_namespace

  repository = var.use_local_chart ? null : var.helm_repository
  chart      = var.helm_chart
  version    = var.use_local_chart ? null : var.operator_version

  values = [
    yamlencode(local.clean_helm_values)
  ]

  depends_on = [kubernetes_namespace.materialize]
}

# Install the metrics-server for monitoring
# Required for the Materialize Console to display cluster metrics
resource "helm_release" "metrics_server" {
  count = var.install_metrics_server ? 1 : 0

  name       = "${var.name_prefix}-metrics-server"
  namespace  = local.monitoring_namespace
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
