locals {
  # Azure has 12-character limit for node pool names
  nodepool_name = substr(replace(var.prefix, "-", ""), 0, 12)

  # Azure doesn't support node taints via Terraform (AKS limitation)
  # Reference: https://github.com/Azure/AKS/issues/2934
  # node_taints = []

  # Auto-scaling configuration - prioritize autoscaling_config object over individual variables
  auto_scaling_enabled = var.autoscaling_config.enabled
  min_nodes            = var.autoscaling_config.enabled ? var.autoscaling_config.min_nodes : null
  max_nodes            = var.autoscaling_config.enabled ? var.autoscaling_config.max_nodes : null
  node_count           = !var.autoscaling_config.enabled ? var.autoscaling_config.node_count : null

  node_labels = merge(
    var.labels,
    {
      "materialize.cloud/disk" = var.enable_disk_setup ? "true" : "false"
      "workload"               = "materialize-instance"
    },
    var.enable_disk_setup ? {
      "materialize.cloud/disk-config-required" = "true"
    } : {}
  )

  disk_setup_name = "disk-setup"

  disk_setup_labels = merge(
    var.labels,
    {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "materialize"
      "app"                          = local.disk_setup_name
    }
  )
}


resource "azurerm_kubernetes_cluster_node_pool" "primary_nodes" {
  name                        = local.nodepool_name
  temporary_name_for_rotation = "${substr(local.nodepool_name, 0, 9)}tmp"
  kubernetes_cluster_id       = var.cluster_id
  vm_size                     = var.vm_size
  auto_scaling_enabled        = local.auto_scaling_enabled
  min_count                   = local.min_nodes
  max_count                   = local.max_nodes
  node_count                  = local.node_count
  vnet_subnet_id              = var.subnet_id
  os_disk_size_gb             = var.disk_size_gb

  node_labels = local.node_labels

  # Azure limitation: Taints cannot be managed via Terraform
  # Reference: https://github.com/Azure/AKS/issues/2934
  # node_taints would go here if supported

  tags = var.tags
}

# resource "kubernetes_namespace" "openebs" {
#   count = var.install_openebs ? 1 : 0

#   metadata {
#     name = var.openebs_namespace
#   }

#   depends_on = [
#     azurerm_kubernetes_cluster_node_pool.primary_nodes
#   ]
# }

# resource "helm_release" "openebs" {
#   count = var.install_openebs ? 1 : 0

#   name       = "openebs"
#   namespace  = kubernetes_namespace.openebs[0].metadata[0].name
#   repository = "https://openebs.github.io/openebs"
#   chart      = "openebs"
#   version    = var.openebs_version

#   set {
#     name  = "engines.replicated.mayastor.enabled"
#     value = "false"
#   }

#   set {
#     name  = "openebs-crds.csi.volumeSnapshots.enabled"
#     value = "false"
#   }

#   depends_on = [
#     kubernetes_namespace.openebs
#   ]
# }

resource "kubernetes_namespace" "disk_setup" {
  count = var.enable_disk_setup ? 1 : 0

  metadata {
    name   = local.disk_setup_name
    labels = local.disk_setup_labels
  }

  depends_on = [
    azurerm_kubernetes_cluster_node_pool.primary_nodes
  ]
}

resource "kubernetes_daemonset" "disk_setup" {
  count = var.enable_disk_setup ? 1 : 0

  depends_on = [
    kubernetes_namespace.disk_setup
  ]

  metadata {
    name      = local.disk_setup_name
    namespace = kubernetes_namespace.disk_setup[0].metadata[0].name
    labels    = local.disk_setup_labels
  }

  spec {
    selector {
      match_labels = {
        app = local.disk_setup_name
      }
    }

    template {
      metadata {
        labels = local.disk_setup_labels
      }

      spec {
        security_context {
          run_as_non_root = false
          run_as_user     = 0
          fs_group        = 0
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        affinity {
          node_affinity {
            required_during_scheduling_ignored_during_execution {
              node_selector_term {
                match_expressions {
                  key      = "materialize.cloud/disk"
                  operator = "In"
                  values   = ["true"]
                }
              }
            }
          }
        }

        toleration {
          key      = "materialize.cloud/disk-unconfigured"
          operator = "Exists"
          effect   = "NoSchedule"
        }

        # Use host network and PID namespace
        host_network = true
        host_pid     = true

        init_container {
          name    = local.disk_setup_name
          image   = var.disk_setup_image
          command = ["/usr/local/bin/configure-disks.sh"]
          args    = ["--cloud-provider", "azure"]
          resources {
            limits = {
              memory = var.disk_setup_container_resource_config.memory_limit
            }
            requests = {
              memory = var.disk_setup_container_resource_config.memory_request
              cpu    = var.disk_setup_container_resource_config.cpu_request
            }
          }

          security_context {
            privileged  = true
            run_as_user = 0
          }

          env {
            name = "NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }

          volume_mount {
            name       = "dev"
            mount_path = "/dev"
          }

          volume_mount {
            name       = "host-root"
            mount_path = "/host"
          }
        }

        # Taints can not be removed: https://github.com/Azure/AKS/issues/2934
        # init_container {
        #   name    = "taint-removal"
        #   image   = var.disk_setup_image
        #   command = ["/usr/local/bin/remove-taint.sh"]
        #   resources {
        #     limits = {
        #       memory = "64Mi"
        #     }
        #     requests = {
        #       memory = "64Mi"
        #       cpu    = "10m"
        #     }
        #   }
        #   security_context {
        #     run_as_user = 0
        #   }
        #   env {
        #     name = "NODE_NAME"
        #     value_from {
        #       field_ref {
        #         field_path = "spec.nodeName"
        #       }
        #     }
        #   }
        #   env {
        #     name  = "TAINT_KEY"
        #     value = "materialize.cloud/disk-unconfigured"
        #   }
        # }

        container {
          name  = "pause"
          image = var.pause_container_image
          resources {
            limits = {
              memory = var.pause_container_resource_config.memory_limit
            }
            requests = {
              memory = var.pause_container_resource_config.memory_request
              cpu    = var.pause_container_resource_config.cpu_request
            }
          }
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root            = true
            run_as_user                = 65534
          }
        }

        volume {
          name = "dev"
          host_path {
            path = "/dev"
          }
        }

        volume {
          name = "host-root"
          host_path {
            path = "/"
          }
        }

        service_account_name = kubernetes_service_account.disk_setup[0].metadata[0].name
      }
    }
  }
}

resource "kubernetes_service_account" "disk_setup" {
  count = var.enable_disk_setup ? 1 : 0

  metadata {
    name      = local.disk_setup_name
    namespace = kubernetes_namespace.disk_setup[0].metadata[0].name
  }
}

resource "kubernetes_cluster_role" "disk_setup" {
  count = var.enable_disk_setup ? 1 : 0

  depends_on = [
    kubernetes_namespace.disk_setup
  ]

  metadata {
    name = local.disk_setup_name
  }
  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["get", "patch"]
  }
}

resource "kubernetes_cluster_role_binding" "disk_setup" {
  count = var.enable_disk_setup ? 1 : 0

  metadata {
    name = local.disk_setup_name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.disk_setup[0].metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.disk_setup[0].metadata[0].name
    namespace = kubernetes_namespace.disk_setup[0].metadata[0].name
  }
}
