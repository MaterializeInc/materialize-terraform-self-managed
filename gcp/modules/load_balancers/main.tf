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

    # https://docs.cloud.google.com/kubernetes-engine/docs/concepts/service-load-balancer-parameters#fw_ip_address
    # we create explicit firewall rules so that we can bound them to target node service account, the default behavior is to allow traffic to all nodes of cluster.
    load_balancer_source_ranges = var.internal ? null : var.ingress_cidr_blocks
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

  lifecycle {
    ignore_changes = [
      # The resource_id is known only after apply,
      # so terraform wants to destroy the resource
      # on any changes to the Materialize CR.
      metadata[0].name,
      spec[0].selector["materialize.cloud/name"],
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
    # https://docs.cloud.google.com/kubernetes-engine/docs/concepts/service-load-balancer-parameters#fw_ip_address
    # we create explicit firewall rules so that we can bound them to target node service account, the default behavior is to allow traffic to all nodes of cluster.
    load_balancer_source_ranges = var.internal ? null : var.ingress_cidr_blocks
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

  lifecycle {
    ignore_changes = [
      # The resource_id is known only after apply,
      # so terraform wants to destroy the resource
      # on any changes to the Materialize CR.
      metadata[0].name,
      spec[0].selector["materialize.cloud/name"],
      metadata[0].annotations["cloud.google.com/neg"]
    ]
  }
  wait_for_load_balancer = true
}

resource "google_compute_firewall" "rules" {
  project     = var.project_id
  name        = "${var.prefix}-lb-ingress-filter-rule"
  network     = var.network_name
  description = "Allow traffic from Load Balancer to Materialize nodes"
  direction   = "INGRESS"
  allow {
    protocol = "tcp"
    ports    = ["8080", "6875", "6876"]
  }
  source_ranges           = var.ingress_cidr_blocks
  target_service_accounts = [var.node_service_account_email]
}
