resource "kubernetes_service" "console_load_balancer" {
  metadata {
    name      = "mz${var.resource_id}-console-lb"
    namespace = var.namespace
    annotations = {
      "service.beta.kubernetes.io/azure-load-balancer-internal" = var.internal ? "true" : "false"
    }
  }

  spec {
    type                        = "LoadBalancer"
    external_traffic_policy     = "Cluster"
    load_balancer_source_ranges = var.ingress_cidr_blocks
    selector = {
      "materialize.cloud/name" = "mz${var.resource_id}-console"
    }
    port {
      name        = "http"
      port        = var.materialize_console_port
      target_port = 8080
      protocol    = "TCP"
    }
  }

  wait_for_load_balancer = true

  lifecycle {
    ignore_changes = [
      # The resource_id is known only after apply,
      # so terraform wants to destroy the resource
      # on any changes to the Materialize CR.
      metadata[0].name,
      spec[0].selector["materialize.cloud/name"],
    ]
  }
}

resource "kubernetes_service" "balancerd_load_balancer" {
  metadata {
    name      = "mz${var.resource_id}-balancerd-lb"
    namespace = var.namespace
    annotations = {
      "service.beta.kubernetes.io/azure-load-balancer-internal" = var.internal ? "true" : "false"
    }
  }

  spec {
    type                        = "LoadBalancer"
    external_traffic_policy     = "Cluster"
    load_balancer_source_ranges = var.ingress_cidr_blocks
    selector = {
      "materialize.cloud/name" = "mz${var.resource_id}-balancerd"
    }
    port {
      name        = "sql"
      port        = var.materialize_balancerd_sql_port
      target_port = 6875
      protocol    = "TCP"
    }
    port {
      name        = "https"
      port        = var.materialize_balancerd_https_port
      target_port = 6876
      protocol    = "TCP"
    }
  }

  wait_for_load_balancer = true

  lifecycle {
    ignore_changes = [
      # The resource_id is known only after apply,
      # so terraform wants to destroy the resource
      # on any changes to the Materialize CR.
      metadata[0].name,
      spec[0].selector["materialize.cloud/name"],
    ]
  }
}
