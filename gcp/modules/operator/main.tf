resource "kubernetes_namespace" "materialize" {
  metadata {
    name = var.operator_namespace
  }
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
          }
        }
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

# Allow egress to Kubernetes API server (required for CRD registration)
# The API server in GKE is a managed service outside the cluster, so we need
# to allow HTTPS egress to the control plane IP. Using 0.0.0.0/0 on port 443
# allows the operator to reach the API server regardless of its IP since API 
# Server IP might change dynamically, hence 0.0.0.0/0 is used
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
