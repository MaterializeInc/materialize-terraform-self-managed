resource "kubernetes_horizontal_pod_autoscaler_v2" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
  }

  spec {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    scale_target_ref {
      api_version = "apps/v1"
      kind        = var.target_kind
      name        = var.target_name
    }

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = var.cpu_target_utilization
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = var.memory_target_utilization
        }
      }
    }

    behavior {
      scale_up {
        stabilization_window_seconds = var.scale_up_stabilization_window
        select_policy                = "Max"

        policy {
          type           = "Pods"
          value          = var.scale_up_pods_per_period
          period_seconds = var.policy_period_seconds
        }

        policy {
          type           = "Percent"
          value          = var.scale_up_percent_per_period
          period_seconds = var.policy_period_seconds
        }
      }

      scale_down {
        stabilization_window_seconds = var.scale_down_stabilization_window
        select_policy                = "Max"

        policy {
          type           = "Percent"
          value          = var.scale_down_percent_per_period
          period_seconds = var.policy_period_seconds
        }
      }
    }
  }
}
