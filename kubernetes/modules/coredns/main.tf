# Custom CoreDNS, since some providers' default CoreDNS can't override its
# config, including cache. Azure: https://github.com/Azure/AKS/issues/3661
locals {
  namespace = "kube-system"
  labels = {
    "k8s-app"        = "kube-dns"
    "provisioned-by" = "materialize"
  }

  # Split-horizon rewrites, appended after `ready`. Empty (no leading newline)
  # when none, so the Corefile does not change for callers without rewrites.
  coredns_rewrites = join("", [
    for r in var.extra_rewrites : "\n    rewrite name ${r.from} ${r.to}"
  ])

  # Corefile with TTL 0 first in the kubernetes plugin block (required for correct parsing)
  corefile = <<-EOF
    .:53 {
        errors
        health {
            lameduck 5s
        }
        ready${local.coredns_rewrites}
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


# Named coredns-custom so it never collides with a platform-bootstrapped coredns
# SA that may exist outside Terraform (e.g. EKS module v20 and earlier).
resource "kubernetes_service_account" "coredns" {
  count = var.create_coredns_service_account ? 1 : 0
  metadata {
    name      = "coredns-custom"
    namespace = local.namespace
  }
}

# Always-present proxy for the ServiceAccount, for the Deployment's
# replace_triggered_by: referencing the counted resource directly fails with
# "no change found" when it has no instances.
resource "terraform_data" "coredns_service_account" {
  input = kubernetes_service_account.coredns[*].metadata[0].uid
}

resource "kubernetes_cluster_role" "coredns" {
  count = var.create_coredns_service_account ? 1 : 0
  metadata {
    name = "coredns-custom"
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

resource "kubernetes_cluster_role_binding" "coredns" {
  count = var.create_coredns_service_account ? 1 : 0
  metadata {
    name = "coredns-custom"
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

resource "kubernetes_config_map" "coredns" {
  metadata {
    name      = "coredns-user-managed"
    namespace = local.namespace
  }

  data = {
    Corefile = local.corefile
  }
}

# EKS module v21+ clusters bootstrap no CoreDNS. Without a Service on the
# cluster DNS IP, kubelet DNS routes nowhere, and policy engines that allowlist
# service ClusterIPs (e.g. the AWS VPC CNI agent) deny all pod DNS egress.
resource "kubernetes_service" "kube_dns" {
  count = var.create_kube_dns_service ? 1 : 0

  metadata {
    name      = "kube-dns"
    namespace = local.namespace
    labels = {
      "k8s-app"                       = "kube-dns"
      "kubernetes.io/cluster-service" = "true"
      "kubernetes.io/name"            = "CoreDNS"
    }
  }

  spec {
    cluster_ip = var.kube_dns_service_cluster_ip
    selector   = local.labels

    port {
      name        = "dns"
      port        = 53
      protocol    = "UDP"
      target_port = 53
    }

    port {
      name        = "dns-tcp"
      port        = 53
      protocol    = "TCP"
      target_port = 53
    }
  }
}

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
        priority_class_name = "system-cluster-critical"
        # Fall back to the platform-bootstrapped CoreDNS service account on
        # clusters where this module does not manage its own.
        service_account_name = var.create_coredns_service_account ? kubernetes_service_account.coredns[0].metadata[0].name : "coredns"

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

  # GKE Warden forbids changing a kube-system workload's SA in place
  # ("no-update-kube-system-service-account"), which can leave cluster DNS down.
  # A replace is a create, which Warden allows.
  lifecycle {
    replace_triggered_by = [terraform_data.coredns_service_account]
  }
}


# Scale down the default kube-dns (and its autoscaler) so only this CoreDNS
# serves DNS. The kubeconfig goes in `environment`, not `input`, which
# terraform_data echoes in cleartext in plan diffs.
#
# No destroy-time scale-up: that would need the kubeconfig in state, and its
# credentials are usually expired by then. Removing only this module (not the
# cluster) means scaling kube-dns back up by hand:
#   kubectl scale deployment <kube-dns deployment> -n kube-system --replicas=2
#   kubectl scale deployment <kube-dns autoscaler deployment> -n kube-system --replicas=1
# Terraform 1.16's sensitive terraform_data `store` could hold it once that is
# an acceptable floor: https://github.com/hashicorp/terraform/pull/38298
resource "terraform_data" "scale_down_kube_dns_autoscaler" {
  count            = var.disable_default_coredns_autoscaler ? 1 : 0
  triggers_replace = [var.cluster_identifier, var.coredns_autoscaler_deployment_to_scale_down, local.namespace]
  provisioner "local-exec" {
    when       = create
    on_failure = fail
    environment = {
      KUBECONFIG_DATA = var.kubeconfig_data
      DEPLOYMENT_NAME = var.coredns_autoscaler_deployment_to_scale_down
      NAMESPACE       = local.namespace
    }
    command = "sh '${path.module}/scripts/scale-down-deployment.sh'"
  }
}

resource "terraform_data" "scale_down_kube_dns" {
  count            = var.disable_default_coredns ? 1 : 0
  triggers_replace = [var.cluster_identifier, var.coredns_deployment_to_scale_down, local.namespace]
  provisioner "local-exec" {
    when       = create
    on_failure = fail
    environment = {
      KUBECONFIG_DATA = var.kubeconfig_data
      DEPLOYMENT_NAME = var.coredns_deployment_to_scale_down
      NAMESPACE       = local.namespace
    }

    command = "sh '${path.module}/scripts/scale-down-deployment.sh'"
  }

  depends_on = [terraform_data.scale_down_kube_dns_autoscaler]
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
