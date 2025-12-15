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

# Custom firewall rule to allow ingress traffic to Materialize nodes (External LB)
# For external load balancers, this restricts access to specific external IP ranges
# This rule targets specific nodes via service account instead of all cluster nodes
resource "google_compute_firewall" "external_rules" {
  count = var.internal ? 0 : 1

  project     = var.project_id
  name        = "${var.prefix}-lb-external-ingress-rule"
  network     = var.network_name
  description = "Allow external traffic from specified CIDR blocks to Materialize nodes via External Load Balancer (custom rule targeting specific service account)"
  direction   = "INGRESS"
  allow {
    protocol = "tcp"
    ports    = ["8080", "6875", "6876"]
  }
  source_ranges           = var.ingress_cidr_blocks
  target_service_accounts = [var.node_service_account_email]
}

# Firewall rule to allow GCP health check traffic
# Required for both internal and external load balancer health checks
# Health checks originate from GCP infrastructure IP ranges
# https://cloud.google.com/load-balancing/docs/firewall-rules
resource "google_compute_firewall" "health_checks" {
  project     = var.project_id
  name        = "${var.prefix}-lb-health-check-rule"
  network     = var.network_name
  description = "Allow GCP load balancer health check traffic to Materialize nodes (required for both internal and external LBs)"
  direction   = "INGRESS"
  allow {
    protocol = "tcp"
    ports    = ["8080", "6875", "6876"]
  }
  # GCP health check IP ranges (same for internal and external LBs)
  # https://cloud.google.com/load-balancing/docs/firewall-rules
  source_ranges           = ["35.191.0.0/16", "130.211.0.0/22"]
  target_service_accounts = [var.node_service_account_email]
}
