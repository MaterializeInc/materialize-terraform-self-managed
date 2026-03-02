# Default deny all ingress/egress in operator namespace
resource "kubernetes_network_policy_v1" "default_deny_operator" {
  count = var.enable_default_deny ? 1 : 0

  metadata {
    name      = "default-deny-all"
    namespace = var.operator_namespace
  }

  spec {
    pod_selector {}

    policy_types = ["Ingress", "Egress"]
  }
}

# Default deny all ingress/egress in instance namespaces
resource "kubernetes_network_policy_v1" "default_deny_instance" {
  for_each = var.enable_default_deny ? toset(var.instance_namespaces) : toset([])

  metadata {
    name      = "default-deny-all"
    namespace = each.value
  }

  spec {
    pod_selector {}

    policy_types = ["Ingress", "Egress"]
  }
}

# Allow all egress from operator namespace (needs API server, DNS, instance access)
resource "kubernetes_network_policy_v1" "allow_all_egress_operator" {
  count = var.enable_default_deny ? 1 : 0

  metadata {
    name      = "allow-all-egress"
    namespace = var.operator_namespace
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
    }
  }
}

# Allow all egress from instance namespaces (storage, database, DNS, etc.)
resource "kubernetes_network_policy_v1" "allow_all_egress_instance" {
  for_each = var.enable_default_deny ? toset(var.instance_namespaces) : toset([])

  metadata {
    name      = "allow-all-egress"
    namespace = each.value
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
    }
  }
}

# Allow ingress from operator namespace to instance namespaces
resource "kubernetes_network_policy_v1" "allow_from_operator" {
  for_each = var.enable_default_deny ? toset(var.instance_namespaces) : toset([])

  metadata {
    name      = "allow-from-operator"
    namespace = each.value
  }

  spec {
    pod_selector {}

    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = var.operator_namespace
          }
        }
      }
    }
  }
}

