resource "kubernetes_namespace" "materialize" {
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

# Re-key state from before `count` was added. Replacing the namespace would
# delete everything in it.
moved {
  from = kubernetes_namespace.monitoring
  to   = kubernetes_namespace.monitoring[0]
}

locals {
  default_helm_values = {
    observability = {
      podMetrics = {
        enabled = true
      }
    }
    networkPolicies = {
      enabled = var.enable_network_policies
      internal = {
        enabled = var.enable_network_policies
      }
      ingress = {
        enabled = var.enable_network_policies
        cidrs   = ["0.0.0.0/0"]
      }
      egress = {
        enabled = var.enable_network_policies
        cidrs   = ["0.0.0.0/0"]
      }
    }
    operator = {
      args = {
        enableLicenseKeyChecks = var.enable_license_key_checks
        installV1CRD           = var.install_v1_crd
      }
      image = var.orchestratord_version == null ? {} : {
        tag = var.orchestratord_version
      },
      cloudProvider = {
        type   = "aws"
        region = var.aws_region
        providers = {
          aws = {
            enabled   = true
            accountID = var.aws_account_id
          }
        }
      }
      clusters = {
        swap_enabled = var.swap_enabled
      }
      nodeSelector = var.operator_node_selector
      tolerations  = var.tolerations
    }

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

# Allow egress to kube-system (DNS, metrics-server, etc.)
resource "kubernetes_network_policy_v1" "allow_kube_system_egress" {
  count = var.enable_network_policies ? 1 : 0

  metadata {
    name      = "allow-kube-system-egress"
    namespace = kubernetes_namespace.materialize.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
      }
    }
  }
}

# Allow egress to the API server (required for CRD registration). The EKS
# control plane is outside the cluster and its IP can change, so allow 443 to any IP.
resource "kubernetes_network_policy_v1" "allow_api_server_egress" {
  count = var.enable_network_policies ? 1 : 0

  metadata {
    name      = "allow-api-server-egress"
    namespace = kubernetes_namespace.materialize.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      to {
        ip_block {
          cidr = "0.0.0.0/0"
        }
      }
      ports {
        protocol = "TCP"
        port     = 443
      }
    }
  }
}

# The operator calls environmentd's https://<svc>:6876/api/login during rollout;
# without this it hangs at status=Applying. Any destination, since one operator
# can manage instances in several namespaces.
resource "kubernetes_network_policy_v1" "allow_environmentd_egress" {
  count = var.enable_network_policies ? 1 : 0

  metadata {
    name      = "allow-environmentd-egress"
    namespace = kubernetes_namespace.materialize.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "materialize-operator"
      }
    }
    policy_types = ["Egress"]

    egress {
      to {
        ip_block {
          cidr = "0.0.0.0/0"
        }
      }
      ports {
        protocol = "TCP"
        port     = 6876
      }
    }
  }
}

# Allow ingress from Kubernetes API server (required for CRD conversion)
resource "kubernetes_network_policy_v1" "allow_api_server_ingress_to_conversion_webhook" {
  count = var.enable_network_policies ? 1 : 0

  metadata {
    name      = "allow-api-server-ingress-to-conversion-webhook"
    namespace = kubernetes_namespace.materialize.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "materialize-operator"
      }
    }
    policy_types = ["Ingress"]

    ingress {
      ports {
        protocol = "TCP"
        port     = 8001
      }
    }
  }
}

# Allow ingress from monitoring namespace (Prometheus scraping)
resource "kubernetes_network_policy_v1" "allow_monitoring_ingress" {
  count = var.enable_network_policies ? 1 : 0

  metadata {
    name      = "allow-monitoring-ingress"
    namespace = kubernetes_namespace.materialize.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = var.monitoring_namespace
          }
        }
      }
    }
  }
}

# Needed for the Console to show cluster metrics.
resource "helm_release" "metrics_server" {
  count = var.install_metrics_server ? 1 : 0

  name       = "${var.name_prefix}-metrics-server"
  namespace  = var.monitoring_namespace
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_version

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

  # Scrapes the HTTPS port that `metrics.enabled` opens to unauthenticated
  # `/metrics` reads. The chart renders the monitor only with both on, and does
  # not check for the monitoring.coreos.com API first.
  set {
    name  = "serviceMonitor.enabled"
    value = var.enable_metrics_server_service_monitor
  }

  dynamic "set" {
    for_each = var.operator_node_selector
    content {
      name  = "nodeSelector.${replace(set.key, ".", "\\.")}"
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
    kubernetes_namespace.monitoring
  ]
}
