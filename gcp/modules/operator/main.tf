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
  # GKE taints Arm nodes with kubernetes.io/arch=arm64:NoSchedule. Images are
  # multi-arch, so always tolerate it; instance_node_selector still picks the pool.
  instance_pod_tolerations = concat(var.instance_pod_tolerations, [
    {
      key      = "kubernetes.io/arch"
      value    = "arm64"
      operator = "Equal"
      effect   = "NoSchedule"
    }
  ])

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
        type   = "gcp"
        region = var.region
        providers = {
          gcp = {
            enabled = true
            nodeUpgradeRolloutTrigger = {
              enabled                  = var.enable_node_upgrade_rollout_trigger
              notificationSubscription = var.node_upgrade_notification_subscription
              clusterName              = var.cluster_name
              clusterLocation          = var.cluster_location
              watchedNodePools         = var.node_upgrade_watched_node_pools
            }
          }
        }
      }
      clusters = {
        swap_enabled = var.swap_enabled
      }
      nodeSelector = var.operator_node_selector
      tolerations  = var.tolerations
    }

    serviceAccount = {
      annotations = var.operator_service_account_annotations
    }

    environmentd = {
      nodeSelector = var.instance_node_selector
      tolerations  = local.instance_pod_tolerations
    }
    clusterd = {
      nodeSelector = var.instance_node_selector
      tolerations  = local.instance_pod_tolerations
    }
    balancerd = {
      nodeSelector = var.instance_node_selector
      tolerations  = local.instance_pod_tolerations
    }
    console = {
      nodeSelector = var.instance_node_selector
      tolerations  = local.instance_pod_tolerations
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

  lifecycle {
    precondition {
      condition = !var.enable_node_upgrade_rollout_trigger || (
        var.node_upgrade_notification_subscription != null
        && var.cluster_name != null
        && var.cluster_location != null
        && var.install_v1_crd
      )
      error_message = "enable_node_upgrade_rollout_trigger requires node_upgrade_notification_subscription, cluster_name, cluster_location, and install_v1_crd."
    }
  }
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

# Allow egress to the API server (required for CRD registration). The GKE
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

# Lets orchestratord get workload identity credentials for the node upgrade
# rollout trigger. Requests go to 169.254.169.254:80, but on Dataplane V2 Cilium
# may enforce on the post-DNAT gke-metadata-server (169.254.169.252:988).
resource "kubernetes_network_policy_v1" "allow_metadata_server_egress" {
  count = var.enable_network_policies && var.enable_node_upgrade_rollout_trigger ? 1 : 0

  metadata {
    name      = "allow-metadata-server-egress"
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
          cidr = "169.254.169.254/32"
        }
      }
      ports {
        protocol = "TCP"
        port     = 80
      }
    }

    egress {
      to {
        ip_block {
          cidr = "169.254.169.252/32"
        }
      }
      ports {
        protocol = "TCP"
        port     = 988
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

# Needed for the Console to show cluster metrics. Off by default since GKE ships
# metrics-server; enable it only if cluster metrics collection is disabled.
# https://cloud.google.com/kubernetes-engine/docs/how-to/configure-metrics
# TODO: confirm with the team and rely on the GKE metrics-server instead.
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
    kubernetes_namespace.monitoring
  ]
}
