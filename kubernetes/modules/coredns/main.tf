# Custom CoreDNS deployment for all cloud providers, because in some cloud providers, the default CoreDNS doesn't support overriding the default configuration including cache.
# Azure reference: https://github.com/Azure/AKS/issues/3661
locals {
  namespace = "kube-system"
  labels = {
    "k8s-app"        = "kube-dns"
    "provisioned-by" = "materialize"
  }

  # Corefile with TTL 0 first in the kubernetes plugin block (required for correct parsing)
  corefile = <<-EOF
    .:53 {
        errors
        health {
            lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
            ttl 0
            pods insecure
            fallthrough in-addr.arpa ip6.arpa
        }
        prometheus :9153
        forward . /etc/resolv.conf {
            max_concurrent 1000
        }
        cache 30 {
            disable denial cluster.local
            disable success cluster.local
        }
        loop
        reload
        loadbalance
    }
  EOF
}


# ServiceAccount for CoreDNS
resource "kubernetes_service_account" "coredns" {
  count = var.create_coredns_service_account ? 1 : 0
  metadata {
    name      = "coredns"
    namespace = local.namespace
  }
}

# ClusterRole for CoreDNS
resource "kubernetes_cluster_role" "coredns" {
  count = var.create_coredns_service_account ? 1 : 0
  metadata {
    name = "system:coredns"
  }

  rule {
    api_groups = [""]
    resources  = ["endpoints", "services", "pods", "namespaces"]
    verbs      = ["list", "watch"]
  }

  rule {
    api_groups = ["discovery.k8s.io"]
    resources  = ["endpointslices"]
    verbs      = ["list", "watch"]
  }
}

# ClusterRoleBinding for CoreDNS
resource "kubernetes_cluster_role_binding" "coredns" {
  count = var.create_coredns_service_account ? 1 : 0
  metadata {
    name = "system:coredns"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.coredns[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.coredns[0].metadata[0].name
    namespace = local.namespace
  }
}

# ConfigMap with Corefile
resource "kubernetes_config_map" "coredns" {
  metadata {
    name      = "coredns-user-managed"
    namespace = local.namespace
  }

  data = {
    Corefile = local.corefile
  }
}

# Custom CoreDNS Deployment
resource "kubernetes_deployment" "coredns" {
  metadata {
    name      = "coredns-custom"
    namespace = local.namespace
    labels = merge(local.labels, {
      "kubernetes.io/name" = "CoreDNS"
    })
  }

  spec {
    replicas = var.replicas

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_unavailable = "1"
      }
    }

    selector {
      match_labels = local.labels
    }

    template {
      metadata {
        labels = local.labels
      }

      spec {
        priority_class_name  = "system-cluster-critical"
        service_account_name = "coredns"

        toleration {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
        }

        node_selector = var.node_selector

        affinity {
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              pod_affinity_term {
                label_selector {
                  match_expressions {
                    key      = "k8s-app"
                    operator = "In"
                    values   = ["kube-dns"]
                  }
                }
                topology_key = "kubernetes.io/hostname"
              }
            }
          }
        }

        container {
          name              = "coredns"
          image             = "coredns/coredns:${var.coredns_version}"
          image_pull_policy = "IfNotPresent"

          args = ["-conf", "/etc/coredns/Corefile"]

          resources {
            limits = {
              memory = var.memory_limit
            }
            requests = {
              cpu    = var.cpu_request
              memory = var.memory_request
            }
          }

          volume_mount {
            name       = "config-volume"
            mount_path = "/etc/coredns"
            read_only  = true
          }

          port {
            container_port = 53
            name           = "dns"
            protocol       = "UDP"
          }

          port {
            container_port = 53
            name           = "dns-tcp"
            protocol       = "TCP"
          }

          port {
            container_port = 9153
            name           = "metrics"
            protocol       = "TCP"
          }

          liveness_probe {
            http_get {
              path   = "/health"
              port   = 8080
              scheme = "HTTP"
            }
            initial_delay_seconds = 60
            timeout_seconds       = 5
            success_threshold     = 1
            failure_threshold     = 5
          }

          readiness_probe {
            http_get {
              path   = "/ready"
              port   = 8181
              scheme = "HTTP"
            }
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              add  = ["NET_BIND_SERVICE"]
              drop = ["all"]
            }
          }
        }

        dns_policy = "Default"

        volume {
          name = "config-volume"
          config_map {
            name = kubernetes_config_map.coredns.metadata[0].name
            items {
              key  = "Corefile"
              path = "Corefile"
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_config_map.coredns,
    terraform_data.scale_down_kube_dns,
    terraform_data.scale_down_kube_dns_autoscaler
  ]
}


resource "terraform_data" "scale_down_kube_dns_autoscaler" {
  count = var.disable_default_coredns_autoscaler ? 1 : 0
  input = {
    KUBECONFIG_DATA = var.kubeconfig_data
    DEPLOYMENT_NAME = var.coredns_autoscaler_deployment_to_scale_down
    NAMESPACE       = local.namespace
  }
  provisioner "local-exec" {
    interpreter = ["/usr/bin/env", "bash", "-c"]
    when        = create
    on_failure  = fail
    environment = self.input
    command     = <<-EOT
      set -euo pipefail

      kubeconfig_file=$(mktemp)
      trap "rm -f '$${kubeconfig_file}'" EXIT
      echo "$${KUBECONFIG_DATA}" > "$${kubeconfig_file}"

      output=$(kubectl --kubeconfig="$${kubeconfig_file}" scale deployment $${DEPLOYMENT_NAME} -n $${NAMESPACE} --replicas=0 2>&1) || {
        if echo "$output" | grep -q "no objects passed to scale"; then
          echo "Deployment $${DEPLOYMENT_NAME} not found, skipping"
          exit 0
        fi
        echo "Error scaling down $${DEPLOYMENT_NAME} deployment: $output"
        exit 1
      }
      echo "Successfully scaled down $${DEPLOYMENT_NAME} to 0 replicas"
    EOT
  }
}

resource "terraform_data" "scale_down_kube_dns" {
  count = var.disable_default_coredns ? 1 : 0
  input = {
    KUBECONFIG_DATA = var.kubeconfig_data
    DEPLOYMENT_NAME = var.coredns_deployment_to_scale_down
    NAMESPACE       = local.namespace
  }
  provisioner "local-exec" {
    interpreter = ["/usr/bin/env", "bash", "-c"]
    when        = create
    on_failure  = fail
    environment = self.input

    command = <<-EOT
      set -euo pipefail

      kubeconfig_file=$(mktemp)
      trap "rm -f '$${kubeconfig_file}'" EXIT
      echo "$${KUBECONFIG_DATA}" > "$${kubeconfig_file}"

      output=$(kubectl --kubeconfig="$${kubeconfig_file}" scale deployment $${DEPLOYMENT_NAME} -n $${NAMESPACE} --replicas=0 2>&1) || {
        if echo "$output" | grep -q "no objects passed to scale"; then
          echo "Deployment $${DEPLOYMENT_NAME} not found, skipping"
          exit 0
        fi
        echo "Error scaling down kube-dns deployment: $output"
        exit 1
      }
      echo "Successfully scaled down $${DEPLOYMENT_NAME} to 0 replicas"
    EOT
  }

  depends_on = [terraform_data.scale_down_kube_dns_autoscaler]
}

# Scale up the default CoreDNS during cleanup
resource "terraform_data" "scale_up_kube_dns_autoscaler" {
  count = var.disable_default_coredns_autoscaler ? 1 : 0
  input = {
    KUBECONFIG_DATA = var.kubeconfig_data
    DEPLOYMENT_NAME = var.coredns_autoscaler_deployment_to_scale_down
    NAMESPACE       = local.namespace
  }
  provisioner "local-exec" {
    interpreter = ["/usr/bin/env", "bash", "-c"]
    when        = destroy
    on_failure  = fail
    environment = self.input
    command     = <<-EOT
      set -euo pipefail

      kubeconfig_file=$(mktemp)
      trap "rm -f '$${kubeconfig_file}'" EXIT
      echo "$${KUBECONFIG_DATA}" > "$${kubeconfig_file}"

      output=$(kubectl --kubeconfig="$${kubeconfig_file}" scale deployment $${DEPLOYMENT_NAME} -n $${NAMESPACE} --replicas=1 2>&1) || {
        if echo "$output" | grep -q "no objects passed to scale"; then
          echo "Deployment $${DEPLOYMENT_NAME} not found, skipping"
          exit 0
        fi
        echo "Error scaling up $${DEPLOYMENT_NAME} deployment: $output"
        exit 1
      }
      echo "Successfully scaled up $${DEPLOYMENT_NAME} to 1 replica"
    EOT
  }
  depends_on = [terraform_data.scale_down_kube_dns]
}

resource "terraform_data" "scale_up_kube_dns" {
  count = var.disable_default_coredns ? 1 : 0

  input = {
    KUBECONFIG_DATA = var.kubeconfig_data
    DEPLOYMENT_NAME = var.coredns_deployment_to_scale_down
    NAMESPACE       = local.namespace
  }
  provisioner "local-exec" {
    interpreter = ["/usr/bin/env", "bash", "-c"]
    when        = destroy
    on_failure  = fail
    environment = self.input
    command     = <<-EOT
      set -euo pipefail

      kubeconfig_file=$(mktemp)
      trap "rm -f '$${kubeconfig_file}'" EXIT
      echo "$${KUBECONFIG_DATA}" > "$${kubeconfig_file}"

      output=$(kubectl --kubeconfig="$${kubeconfig_file}" scale deployment $${DEPLOYMENT_NAME} -n $${NAMESPACE} --replicas=2 2>&1) || {
        if echo "$output" | grep -q "no objects passed to scale"; then
          echo "Deployment $${DEPLOYMENT_NAME} not found, skipping"
          exit 0
        fi
        echo "Error scaling up kube-dns deployment: $output"
        exit 1
      }
      echo "Successfully scaled up $${DEPLOYMENT_NAME} to 2 replicas"
    EOT
  }

  depends_on = [terraform_data.scale_up_kube_dns_autoscaler]
}

module "hpa" {
  source = "../hpa"

  name        = "coredns-custom"
  namespace   = local.namespace
  target_name = kubernetes_deployment.coredns.metadata[0].name
  target_kind = "Deployment"

  min_replicas = var.hpa_min_replicas
  max_replicas = var.hpa_max_replicas

  cpu_target_utilization    = var.hpa_cpu_target_utilization
  memory_target_utilization = var.hpa_memory_target_utilization

  scale_up_stabilization_window = var.hpa_scale_up_stabilization_window
  scale_up_pods_per_period      = var.hpa_scale_up_pods_per_period
  scale_up_percent_per_period   = var.hpa_scale_up_percent_per_period

  scale_down_stabilization_window = var.hpa_scale_down_stabilization_window
  scale_down_percent_per_period   = var.hpa_scale_down_percent_per_period

  policy_period_seconds = var.hpa_policy_period_seconds

  depends_on = [kubernetes_deployment.coredns]
}
