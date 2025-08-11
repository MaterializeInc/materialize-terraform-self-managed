resource "kubernetes_service" "console_load_balancer" {
  metadata {
    name      = "mz${var.resource_id}-console-lb"
    namespace = var.namespace
    annotations = {
      "networking.gke.io/load-balancer-type" = var.internal ? "Internal" : "External"
    }
  }

  spec {
    type                    = "LoadBalancer"
    external_traffic_policy = "Local"
    selector = {
      "materialize.cloud/name" = "mz${var.resource_id}-console"
    }
    port {
      name        = var.materialize_console_port_config.name
      port        = var.materialize_console_port_config.port
      target_port = var.materialize_console_port_config.target_port
      protocol    = var.materialize_console_port_config.protocol
    }
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["cloud.google.com/neg"]
    ]
  }
  wait_for_load_balancer = true
}

resource "kubernetes_service" "balancerd_load_balancer" {
  metadata {
    name      = "mz${var.resource_id}-balancerd-lb"
    namespace = var.namespace
    annotations = {
      "networking.gke.io/load-balancer-type" = var.internal ? "Internal" : "External"
    }
  }

  spec {
    type                    = "LoadBalancer"
    external_traffic_policy = "Local"
    selector = {
      "materialize.cloud/name" = "mz${var.resource_id}-balancerd"
    }
    port {
      name        = var.materialize_balancerd_sql_port_config.name
      port        = var.materialize_balancerd_sql_port_config.port
      target_port = var.materialize_balancerd_sql_port_config.target_port
      protocol    = var.materialize_balancerd_sql_port_config.protocol
    }
    port {
      name        = var.materialize_balancerd_https_port_config.name
      port        = var.materialize_balancerd_https_port_config.port
      target_port = var.materialize_balancerd_https_port_config.target_port
      protocol    = var.materialize_balancerd_https_port_config.protocol
    }
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["cloud.google.com/neg"]
    ]
  }
  wait_for_load_balancer = true
}
